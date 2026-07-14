import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'auth/onboarding_flow.dart';
import 'auth/splash_screen.dart';
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

  // Restore any existing session; the UI shows a splash until this resolves.
  authController.bootstrap();

  runApp(DriverApp(
    themeController: themeController,
    authController: authController,
    driverController: driverController,
    driverTripApi: driverTripApi,
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
  });

  final ThemeController themeController;
  final AuthController authController;
  final DriverController driverController;
  final DriverTripApi driverTripApi;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: authController),
        ChangeNotifierProvider<DriverController>.value(value: driverController),
        Provider<DriverTripApi>.value(value: driverTripApi),
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
      AuthStatus.onboarding => const OnboardingFlow(),
      AuthStatus.authenticated => const DriverGate(),
    };
  }
}
