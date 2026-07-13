import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'theme_controller.dart';

/// The shared application shell for the rider, driver and admin apps.
///
/// Wires [MaterialApp] to the design system once, in one place:
/// - light/dark [ThemeData] from [AppTheme];
/// - `themeMode` bound to a [ThemeController] (rebuilds on change);
/// - Arabic-first: locale `ar`, RTL [Directionality], Material/Cupertino
///   localizations.
///
/// A full re-skin stays a change to the theme files only — apps just supply a
/// [home] and [title].
class TaxiApp extends StatelessWidget {
  const TaxiApp({
    super.key,
    required this.themeController,
    required this.home,
    this.title = '',
    this.navigatorKey,
  });

  final ThemeController themeController;
  final Widget home;
  final String title;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    // provider is the app-wide state approach (see CLAUDE.md → State
    // management). Expose the ThemeController to the whole tree — so any screen
    // can `context.read<ThemeController>()` (e.g. a future settings toggle) —
    // and rebuild the MaterialApp when the mode changes. `.value` because the
    // controller is created once at startup and owned by `main()`, not here.
    return ChangeNotifierProvider<ThemeController>.value(
      value: themeController,
      child: Consumer<ThemeController>(
        builder: (context, controller, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: title,
            navigatorKey: navigatorKey,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: controller.mode,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: home,
          );
        },
      ),
    );
  }
}
