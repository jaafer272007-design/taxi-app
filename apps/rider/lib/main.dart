import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/onboarding_flow.dart';
import 'auth/splash_screen.dart';
import 'config/app_config.dart';
import 'core/token_store.dart';
import 'home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = await ThemeController.create();

  final tokenStore = SecureTokenStore();
  final authController = AuthController(
    api: DioAuthApi(baseUrl: AppConfig.apiBaseUrl, tokenStore: tokenStore),
    tokenStore: tokenStore,
  );
  // Restore any existing session; the UI shows a splash until this resolves.
  authController.bootstrap();

  runApp(RiderApp(
    themeController: themeController,
    authController: authController,
  ));
}

/// Root of the rider app. Theming/localization/RTL come from the shared
/// [TaxiApp]; the [AuthController] is provided above it so every screen can
/// reach it (`context.read/watch<AuthController>()`).
class RiderApp extends StatelessWidget {
  const RiderApp({
    super.key,
    required this.themeController,
    required this.authController,
  });

  final ThemeController themeController;
  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: authController,
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
      AuthStatus.authenticated => const RiderHome(),
    };
  }
}
