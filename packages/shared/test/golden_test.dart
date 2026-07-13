import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared/shared.dart';

/// Golden (visual snapshot) tests for the whole design system.
///
/// Each test renders a slice of the system — color tokens, the type scale, or
/// every base widget — under BOTH the light and dark themes, RTL and Arabic,
/// and snapshots it to a PNG under `test/goldens/`. CI generates the baselines
/// on the first run and commits them; afterwards these tests fail (and emit a
/// diff image) whenever a change alters rendering — a visual regression guard.
///
/// Cairo renders as the real font because it is bundled as a package asset
/// (`assets/fonts/`) which `google_fonts` discovers by filename — no network,
/// fully deterministic.
void main() {
  setUpAll(() async {
    // flutter_test does not auto-load dependency package fonts, so the Lucide
    // icon glyphs would render as tofu boxes. Load the icon font explicitly;
    // an IconData with a fontPackage resolves to family
    // 'packages/<package>/<family>'.
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(
              rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf')))
        .load();

    // Never hit the network in tests: force google_fonts to use the bundled
    // Cairo assets, then warm every weight the theme uses so the first painted
    // frame already has real Cairo (not the fallback font).
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.light();
    AppTheme.dark();
    await GoogleFonts.pendingFonts();
  });

  group('color tokens', () {
    testWidgets('light', (tester) async {
      await _matchGolden(tester,
          name: 'colors_light',
          brightness: Brightness.light,
          height: 620,
          child: const ColorTokensGallery());
    });
    testWidgets('dark', (tester) async {
      await _matchGolden(tester,
          name: 'colors_dark',
          brightness: Brightness.dark,
          height: 620,
          child: const ColorTokensGallery());
    });
  });

  group('type scale', () {
    testWidgets('light', (tester) async {
      await _matchGolden(tester,
          name: 'typography_light',
          brightness: Brightness.light,
          height: 560,
          child: const TypeScaleGallery());
    });
    testWidgets('dark', (tester) async {
      await _matchGolden(tester,
          name: 'typography_dark',
          brightness: Brightness.dark,
          height: 560,
          child: const TypeScaleGallery());
    });
  });

  group('base widgets', () {
    testWidgets('light', (tester) async {
      await _matchGolden(tester,
          name: 'widgets_light',
          brightness: Brightness.light,
          height: 1420,
          child: const WidgetShowcaseGallery());
    });
    testWidgets('dark', (tester) async {
      await _matchGolden(tester,
          name: 'widgets_dark',
          brightness: Brightness.dark,
          height: 1420,
          child: const WidgetShowcaseGallery());
    });
  });
}

/// Fixed capture width (a phone-ish column).
const double _width = 440;

/// Renders [child] under the app theme for [brightness], RTL + Arabic, at a
/// fixed surface size, then compares against `goldens/[name].png`.
Future<void> _matchGolden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
  required double height,
}) async {
  const dpr = 2.0; // crisp, retina-ish snapshots
  tester.view.physicalSize = Size(_width * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme =
      brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();
  final bg = theme.extension<AppColors>()!.background;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          body: SizedBox(
            width: _width,
            height: height,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );

  // Two fixed pumps from the deterministic test clock — enough to lay out and
  // paint (including the loading button's spinner) without pumpAndSettle, which
  // would hang forever on the indeterminate spinner.
  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
