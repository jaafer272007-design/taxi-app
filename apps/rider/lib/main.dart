import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'auth/onboarding_copy.dart';
import 'booking/booking_api.dart';
import 'config/app_config.dart';
import 'home/home_shell.dart';
import 'trip/trip_api.dart';
import 'trip/trip_search_controller.dart';

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
  final tripSearchController =
      TripSearchController(api: DioTripApi(apiClient.dio));
  final bookingApi = DioBookingApi(apiClient.dio);
  final notificationsController = NotificationsController(
    api: DioNotificationApi(apiClient.dio),
  );

  // Restore any existing session; the UI shows a splash until this resolves.
  authController.bootstrap();

  runApp(RiderApp(
    themeController: themeController,
    authController: authController,
    tripSearchController: tripSearchController,
    bookingApi: bookingApi,
    notificationsController: notificationsController,
  ));
}

/// Root of the rider app. Theming/RTL come from the shared [TaxiApp]; the
/// controllers are provided above it so every screen can reach them.
class RiderApp extends StatelessWidget {
  const RiderApp({
    super.key,
    required this.themeController,
    required this.authController,
    required this.tripSearchController,
    required this.bookingApi,
    required this.notificationsController,
  });

  final ThemeController themeController;
  final AuthController authController;
  final TripSearchController tripSearchController;
  final BookingApi bookingApi;
  final NotificationsController notificationsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: authController),
        ChangeNotifierProvider<TripSearchController>.value(
          value: tripSearchController,
        ),
        Provider<BookingApi>.value(value: bookingApi),
        // Map picker services (concrete impls live here; the booking screen
        // depends only on the LocationService / ReverseGeocoder interfaces).
        Provider<LocationService>(
          create: (_) => const GeolocatorLocationService(),
        ),
        Provider<ReverseGeocoder>(create: (_) => NominatimReverseGeocoder()),
        // Opens tel: / wa.me / geo: links — same containment as above: screens
        // depend on the LinkLauncher interface, not on url_launcher.
        Provider<LinkLauncher>(create: (_) => const UrlLinkLauncher()),
        ChangeNotifierProvider<NotificationsController>.value(
          value: notificationsController,
        ),
      ],
      child: TaxiApp(
        title: 'تكسي مشترك — الراكب',
        themeController: themeController,
        home: const _RiderRouter(),
      ),
    );
  }
}

/// Chooses the top-level screen from the auth status.
class _RiderRouter extends StatelessWidget {
  const _RiderRouter();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthController>().status;
    return switch (status) {
      AuthStatus.unknown => const SplashScreen(),
      AuthStatus.onboarding => const OnboardingFlow(copy: riderOnboardingCopy),
      // The announcer and the notification poll live INSIDE the authenticated
      // branch: there is nobody to notify before a session exists, and polling
      // an endpoint that would 401 is just noise.
      AuthStatus.authenticated => PollingScope(
          interval: kNotificationsPollInterval,
          // App-wide, so it keeps running behind a pushed route and on every
          // tab: the whole point is that a rider hears about a cancellation
          // whatever screen they happen to be on.
          pauseWhenObscured: false,
          onPoll: context.read<NotificationsController>().refreshSilently,
          child: const NotificationAnnouncer(child: HomeShell()),
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
