import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: title,
          navigatorKey: navigatorKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.mode,
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
    );
  }
}
