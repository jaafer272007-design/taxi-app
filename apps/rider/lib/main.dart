import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'auth/onboarding_flow.dart';
import 'auth/splash_screen.dart';
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

  // Restore any existing session; the UI shows a splash until this resolves.
  authController.bootstrap();

  runApp(RiderApp(
    themeController: themeController,
    authController: authController,
    tripSearchController: tripSearchController,
    bookingApi: bookingApi,
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
  });

  final ThemeController themeController;
  final AuthController authController;
  final TripSearchController tripSearchController;
  final BookingApi bookingApi;

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
      AuthStatus.onboarding => const OnboardingFlow(),
      AuthStatus.authenticated => const HomeShell(),
    };
  }
}
