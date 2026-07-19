import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:rider/trip/widgets/trip_card.dart';
import 'package:rider/trip/widgets/trip_state_views.dart';
import 'package:shared/shared.dart';

import 'support/trip_fakes.dart';

Widget _host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('trip card shows driver, time, price and a success seats pill',
      (tester) async {
    await tester.pumpWidget(_host(TripCard(trip: tripFixture(seatsAvailable: 3))));

    expect(find.text('علي حسن'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget); // 04:30 UTC → Baghdad
    expect(find.textContaining('6,000'), findsOneWidget);
    expect(find.textContaining('Toyota Corolla'), findsOneWidget);
    expect(find.text('3 مقاعد متاحة'), findsOneWidget);
  });

  testWidgets('last seat shows the warning pill', (tester) async {
    await tester.pumpWidget(_host(TripCard(trip: tripFixture(seatsAvailable: 1))));

    expect(find.text('مقعد واحد فقط'), findsOneWidget);
    expect(find.text('1 مقاعد متاحة'), findsNothing);
  });

  testWidgets('women/family trip shows a distinct badge', (tester) async {
    await tester.pumpWidget(
      _host(TripCard(trip: tripFixture(tripType: TripType.womenFamily))),
    );

    expect(find.text('نسائية/عائلية'), findsOneWidget);
  });

  testWidgets('general trip shows no women/family badge', (tester) async {
    await tester.pumpWidget(_host(TripCard(trip: tripFixture())));

    expect(find.text('نسائية/عائلية'), findsNothing);
  });

  testWidgets('a female driver is shown subtly as سائقة', (tester) async {
    await tester.pumpWidget(
      _host(TripCard(trip: tripFixture(driverGender: Gender.female))),
    );

    expect(find.text('سائقة'), findsOneWidget);
  });

  testWidgets('empty state shows the no-trips message', (tester) async {
    await tester.pumpWidget(_host(const TripEmptyView()));

    expect(
        find.text('لا توجد رحلات متاحة على هذا المسار حالياً'), findsOneWidget);
  });

  testWidgets(
      'filtered empty state (female driver) tailors copy and offers clear',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(_host(TripEmptyView(
      driverGender: Gender.female,
      onClearFilters: () => cleared = true,
    )));

    expect(
      find.text('لا توجد رحلات بسائقة امرأة على هذا المسار حالياً'),
      findsOneWidget,
    );
    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'إزالة الفلاتر'),
    );
    btn.onPressed!();
    expect(cleared, isTrue);
  });

  testWidgets('women/family filtered empty state tailors its copy',
      (tester) async {
    await tester.pumpWidget(_host(TripEmptyView(
      tripType: TripType.womenFamily,
      onClearFilters: () {},
    )));

    expect(
      find.text('لا توجد رحلات نسائية-عائلية على هذا المسار حالياً'),
      findsOneWidget,
    );
  });
}
