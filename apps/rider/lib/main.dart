import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the persisted theme mode (defaults to ThemeMode.system) BEFORE the
  // first frame, so the app opens in the appearance the user last chose.
  final themeController = await ThemeController.create();
  runApp(RiderApp(themeController: themeController));
}

/// Root of the rider app. All theming/localization/RTL wiring lives in the
/// shared [TaxiApp]; here we only supply the controller and the first screen.
class RiderApp extends StatelessWidget {
  const RiderApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return TaxiApp(
      title: 'تكسي مشترك — الراكب',
      themeController: themeController,
      home: const RiderHome(),
    );
  }
}
