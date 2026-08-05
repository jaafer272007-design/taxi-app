import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared/shared.dart';

import 'support/contact_fakes.dart';
import 'support/map_fakes.dart';

/// Golden tests for the shared [AppMapPicker] — the default pin + confirm bar,
/// and the permission-denied state — BOTH light and dark, RTL, Arabic, real
/// Cairo + Lucide fonts, at a 390×844 phone frame. Tiles are stubbed
/// (`usePlaceholderTiles`) so no network is hit; the golden shows the pin + UI
/// chrome over a neutral map placeholder (real OSM tiles are a live-run item).
void main() {
  setUpAll(() async {
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(
              rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf')))
        .load();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.light();
    AppTheme.dark();
    await GoogleFonts.pendingFonts();
  });

  group('map picker', () {
    testWidgets('light', (t) async {
      await _golden(t, name: 'map_picker_light', brightness: Brightness.light);
    });
    testWidgets('dark', (t) async {
      await _golden(t, name: 'map_picker_dark', brightness: Brightness.dark);
    });
  });

  group('map picker permission denied', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'map_picker_denied_light',
          brightness: Brightness.light,
          interact: _tapUseMyLocation);
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'map_picker_denied_dark',
          brightness: Brightness.dark,
          interact: _tapUseMyLocation);
    });
  });

  // The read-only view: a point somebody else chose, with the hand-off to a
  // maps app. No confirm bar and no "use my location" — the whole difference
  // from the picker above is visible in one glance at these two.
  group('map view', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'map_view_light', brightness: Brightness.light, child: _view());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'map_view_dark', brightness: Brightness.dark, child: _view());
    });
  });

  // Reverse geocoding failed. The address line shows coordinates rather than
  // nothing — a state that IS reached in the field, so it gets a screenshot.
  group('map view without a label', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'map_view_no_label_light',
          brightness: Brightness.light,
          child: _viewNoLabel());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'map_view_no_label_dark',
          brightness: Brightness.dark,
          child: _viewNoLabel());
    });
  });
}

AppMapView _view() => AppMapView(
      point: const LocationPoint(
          lat: 32.616, lng: 44.0242, label: 'طريق الحر، حي الزيتون'),
      launcher: FakeLinkLauncher(),
      title: 'نقطة الانطلاق',
      usePlaceholderTiles: true,
    );

AppMapView _viewNoLabel() => AppMapView(
      point: const LocationPoint(lat: 31.999, lng: 44.3148),
      launcher: FakeLinkLauncher(),
      title: 'نقطة النزول',
      usePlaceholderTiles: true,
    );

AppMapPicker _picker() => AppMapPicker(
      initialCenter: const LocationPoint(lat: 32.616, lng: 44.024),
      locationService: FakeLocationService.denied(),
      usePlaceholderTiles: true,
      fallbackLabel: 'كربلاء - النقطة المحددة',
      onPointSelected: (_) {},
    );

Future<void> _tapUseMyLocation(WidgetTester t) async {
  t
      .widget<AppButton>(find.widgetWithText(AppButton, 'استخدم موقعي'))
      .onPressed!();
  await t.pump();
  await t.pump();
}

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  Future<void> Function(WidgetTester)? interact,
  Widget? child,
}) async {
  const width = 390.0;
  const height = 844.0;
  const dpr = 2.0;
  tester.view.physicalSize = const Size(width * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme =
      brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();

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
          textDirection: TextDirection.rtl, child: child ?? _picker()),
    ),
  );

  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));
  if (interact != null) await interact(tester);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
