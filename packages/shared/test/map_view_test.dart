import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/contact_fakes.dart';

/// [AppMapView] — the read-only point, its label fallback, and the navigation
/// hand-off.
void main() {
  Future<void> host(
    WidgetTester tester, {
    required LocationPoint point,
    required LinkLauncher launcher,
    VoidCallback? onNavigationUnavailable,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AppMapView(
            point: point,
            launcher: launcher,
            title: 'نقطة الانطلاق',
            usePlaceholderTiles: true,
            onNavigationUnavailable: onNavigationUnavailable,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));
  }

  group('label', () {
    test('uses the reverse-geocoded name when there is one', () {
      expect(
        AppMapView.displayLabel(const LocationPoint(
            lat: 32.6, lng: 44.0, label: 'قرية الغدير السكنية')),
        'قرية الغدير السكنية',
      );
    });

    test('falls back to coordinates when geocoding gave nothing', () {
      // Reverse geocoding fails often — offline, rate-limited, or an unnamed
      // road — so a blank address line is a normal state, not an edge case.
      // Coordinates can at least be read down a phone or pasted into a map.
      expect(
        AppMapView.displayLabel(const LocationPoint(lat: 31.999, lng: 44.3148)),
        '31.99900, 44.31480',
      );
    });

    test('treats a whitespace-only label as missing', () {
      expect(
        AppMapView.displayLabel(
            const LocationPoint(lat: 31.999, lng: 44.3148, label: '   ')),
        '31.99900, 44.31480',
      );
    });
  });

  testWidgets('shows the address and its coordinates', (t) async {
    await host(
      t,
      point: const LocationPoint(
          lat: 32.616, lng: 44.0242, label: 'طريق الحر، حي الزيتون'),
      launcher: FakeLinkLauncher(),
    );

    expect(find.text('طريق الحر، حي الزيتون'), findsOneWidget);
    expect(find.text('32.61600, 44.02420'), findsOneWidget);
  });

  testWidgets('renders the coordinate fallback LTR, and only once', (t) async {
    await host(
      t,
      point: const LocationPoint(lat: 31.999, lng: 44.3148),
      launcher: FakeLinkLauncher(),
    );

    final found = find.text('31.99900, 44.31480');
    // Once, not twice: with no name to show, printing the coordinates as both
    // the title and its own subtitle would be pure noise.
    expect(found, findsOneWidget);
    expect(t.widget<Text>(found).textDirection, TextDirection.ltr);
  });

  testWidgets('the navigation button opens a geo: pin', (t) async {
    final launcher = FakeLinkLauncher();
    await host(
      t,
      point: const LocationPoint(lat: 32.616, lng: 44.0242, label: 'الحرم'),
      launcher: launcher,
    );

    t.widget<AppButton>(find.widgetWithText(AppButton, 'الاتجاهات في تطبيق الخرائط')).onPressed!();
    await t.pump();

    expect(launcher.last!.scheme, 'geo');
    expect(launcher.last.toString(), startsWith('geo:32.616000,44.024200?q='));
  });

  testWidgets('falls back to the web map when the device has no geo: handler',
      (t) async {
    final launcher = FakeLinkLauncher.withoutGeo();
    await host(
      t,
      point: const LocationPoint(lat: 32.616, lng: 44.0242, label: 'الحرم'),
      launcher: launcher,
    );

    t.widget<AppButton>(find.widgetWithText(AppButton, 'الاتجاهات في تطبيق الخرائط')).onPressed!();
    await t.pump();

    // It TRIED geo: first — the order matters, since geo: is the one that opens
    // the driver's own maps app rather than forcing Google.
    expect(launcher.attempted.first.scheme, 'geo');
    expect(launcher.last!.host, 'www.google.com');
  });

  testWidgets('reports when nothing at all could open', (t) async {
    var reported = false;
    await host(
      t,
      point: const LocationPoint(lat: 32.6, lng: 44.0, label: 'الحرم'),
      launcher: FakeLinkLauncher.deaf(),
      onNavigationUnavailable: () => reported = true,
    );

    t.widget<AppButton>(find.widgetWithText(AppButton, 'الاتجاهات في تطبيق الخرائط')).onPressed!();
    await t.pump();

    expect(reported, isTrue);
  });

  testWidgets('offers no way to change the point — it is somebody else\'s',
      (t) async {
    await host(
      t,
      point: const LocationPoint(lat: 32.6, lng: 44.0, label: 'الحرم'),
      launcher: FakeLinkLauncher(),
    );

    expect(find.widgetWithText(AppButton, 'تأكيد النقطة'), findsNothing);
    expect(find.widgetWithText(AppButton, 'استخدم موقعي'), findsNothing);
  });
}
