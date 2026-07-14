import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/map_fakes.dart';

Widget _host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

AppButton _button(WidgetTester t, String label) =>
    t.widget<AppButton>(find.widgetWithText(AppButton, label));

void main() {
  testWidgets('confirm returns the centered point as a LocationPoint',
      (t) async {
    LocationPoint? captured;
    await t.pumpWidget(_host(AppMapPicker(
      initialCenter: const LocationPoint(lat: 32.0, lng: 44.3),
      locationService: FakeLocationService.denied(),
      usePlaceholderTiles: true,
      fallbackLabel: 'النجف - النقطة المحددة',
      onPointSelected: (p) => captured = p,
    )));
    await t.pump();

    _button(t, 'تأكيد النقطة').onPressed!();
    await t.pump();

    expect(captured, isNotNull);
    expect(captured!.lat, closeTo(32.0, 0.01));
    expect(captured!.lng, closeTo(44.3, 0.01));
    // No geocoder → the fallback label is used.
    expect(captured!.label, 'النجف - النقطة المحددة');
  });

  testWidgets('use-my-location denied shows a graceful Arabic message',
      (t) async {
    final service = FakeLocationService.denied();
    await t.pumpWidget(_host(AppMapPicker(
      initialCenter: const LocationPoint(lat: 32.0, lng: 44.3),
      locationService: service,
      usePlaceholderTiles: true,
      onPointSelected: (_) {},
    )));
    await t.pump();

    _button(t, 'استخدم موقعي').onPressed!();
    await t.pump();
    await t.pump();

    expect(service.calls, 1);
    expect(find.textContaining('رفض إذن الموقع'), findsOneWidget);
  });

  testWidgets('use-my-location success recenters and confirms that point',
      (t) async {
    LocationPoint? captured;
    await t.pumpWidget(_host(AppMapPicker(
      initialCenter: const LocationPoint(lat: 32.0, lng: 44.3),
      locationService: FakeLocationService.ok(
          const LocationPoint(lat: 31.5, lng: 44.1, label: 'موقعي')),
      usePlaceholderTiles: true,
      onPointSelected: (p) => captured = p,
    )));
    await t.pump();

    _button(t, 'استخدم موقعي').onPressed!();
    await t.pump();
    await t.pump();

    _button(t, 'تأكيد النقطة').onPressed!();
    await t.pump();

    expect(captured, isNotNull);
    expect(captured!.lat, closeTo(31.5, 0.01));
    expect(captured!.lng, closeTo(44.1, 0.01));
    expect(captured!.label, 'موقعي');
  });
}
