import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'auth/onboarding_copy.dart';
import 'config/app_config.dart';
import 'driver/driver_api.dart';
import 'driver/driver_controller.dart';
import 'driver/driver_gate.dart';
import 'driver/image_picker_document_picker.dart';
import 'trip/driver_trip_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = await ThemeController.create();

  final tokenStore = SecureTokenStore();
  final apiClient =
      ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenStore: tokenStore);

  final authController = AuthController(
    api: DioAuthApi(apiClient.dio),
    tokenStore: tokenStore,
  );
  final driverController = DriverController(
    api: DioDriverApi(apiClient.dio),
    picker: ImagePickerDocumentPicker(),
  );
  final driverTripApi = DioDriverTripApi(apiClient.dio);
  final notificationsController = NotificationsController(
    api: DioNotificationApi(apiClient.dio),
  );

  // Restore any existing session; the UI shows a splash until this resolves.
  authController.bootstrap();

  runApp(DriverApp(
    themeController: themeController,
    authController: authController,
    driverController: driverController,
    driverTripApi: driverTripApi,
    notificationsController: notificationsController,
  ));
}

/// Root of the driver app. Theming/RTL come from the shared [TaxiApp]; the
/// controllers are provided above it (and above the Navigator, so pushed routes
/// like the documents re-upload see the driver controller too).
class DriverApp extends StatelessWidget {
  const DriverApp({
    super.key,
    required this.themeController,
    required this.authController,
    required this.driverController,
    required this.driverTripApi,
    required this.notificationsController,
  });

  final ThemeController themeController;
  final AuthController authController;
  final DriverController driverController;
  final DriverTripApi driverTripApi;
  final NotificationsController notificationsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: authController),
        ChangeNotifierProvider<DriverController>.value(value: driverController),
        Provider<DriverTripApi>.value(value: driverTripApi),
        // Opens tel: / wa.me / geo: links. The concrete impl lives here; every
        // screen depends only on the LinkLauncher interface, so widget tests
        // inject a fake and assert the URL a tap produced.
        Provider<LinkLauncher>(create: (_) => const UrlLinkLauncher()),
        ChangeNotifierProvider<NotificationsController>.value(
          value: notificationsController,
        ),
      ],
      child: TaxiApp(
        title: 'تكسي مشترك — السائق',
        themeController: themeController,
        home: const _DriverRouter(),
      ),
    );
  }
}

/// Chooses the top-level screen from the auth status.
class _DriverRouter extends StatelessWidget {
  const _DriverRouter();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthController>().status;
    return switch (status) {
      AuthStatus.unknown => const SplashScreen(),
      AuthStatus.onboarding => const OnboardingFlow(copy: driverOnboardingCopy),
      // Inside the authenticated branch only: nobody to notify before a
      // session exists, and the endpoint would 401.
      AuthStatus.authenticated => PollingScope(
          interval: kNotificationsPollInterval,
          // App-wide: keeps running behind a pushed route and on every tab.
          // A new booking should reach the driver while they are posting the
          // next trip, not only from the one screen that happens to poll.
          pauseWhenObscured: false,
          onPoll: context.read<NotificationsController>().refreshSilently,
          child: const NotificationAnnouncer(child: DriverGate()),
        ),
    };
  }
}

/// How often the badge re-checks for new events.
///
/// 30 seconds, everywhere, on every screen — this is the one poll that is not
/// tied to a particular view, because the whole point is that a rider learns
/// their trip was cancelled *whatever they are looking at*. It is also the
/// cheapest: a list of at most fifty rows and a count.
const Duration kNotificationsPollInterval = Duration(seconds: 30);
