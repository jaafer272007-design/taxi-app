import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

Widget _host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  test('the canonical list has all 18 governorate cities', () {
    expect(kIraqiCities.length, 18);
    // A few spot checks (key → Arabic display).
    expect(cityArName('Baghdad'), 'بغداد');
    expect(cityArName('Najaf'), 'النجف');
    expect(cityArName('Basra'), 'البصرة');
    // Unknown key falls back to itself (never blank).
    expect(cityArName('Nowhere'), 'Nowhere');
  });

  group('AppCityField', () {
    testWidgets('shows the selected city name in Arabic', (tester) async {
      await tester.pumpWidget(_host(
        AppCityField(label: 'من', cityKey: 'Najaf', onChanged: (_) {}),
      ));
      expect(find.text('من'), findsOneWidget);
      expect(find.text('النجف'), findsOneWidget);
    });

    testWidgets('prompts to choose when nothing is selected', (tester) async {
      await tester.pumpWidget(_host(
        AppCityField(label: 'إلى', cityKey: null, onChanged: (_) {}),
      ));
      expect(find.text('اختر المدينة'), findsOneWidget);
    });
  });

  group('AppCityPickerSheet', () {
    testWidgets('lists every city and returns the tapped one', (tester) async {
      String? picked;
      await tester.pumpWidget(_host(
        AppCityPickerSheet(selected: 'Najaf', onSelect: (k) => picked = k),
      ));

      // A sample of the 18 render.
      expect(find.text('بغداد'), findsOneWidget);
      expect(find.text('الموصل'), findsOneWidget);
      expect(find.text('البصرة'), findsOneWidget);

      await tester.tap(find.text('بغداد'));
      expect(picked, 'Baghdad');
    });

    testWidgets('an excluded city cannot be picked', (tester) async {
      String? picked;
      await tester.pumpWidget(_host(
        AppCityPickerSheet(
          selected: 'Najaf',
          excludeKey: 'Karbala',
          onSelect: (k) => picked = k,
        ),
      ));

      await tester.tap(find.text('كربلاء'));
      expect(picked, isNull); // excluded → tap ignored
    });
  });
}
