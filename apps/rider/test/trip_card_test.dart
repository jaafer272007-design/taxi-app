import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('empty state shows the no-trips message', (tester) async {
    await tester.pumpWidget(_host(const TripEmptyView()));

    expect(find.text('لا توجد رحلات متاحة على هذا المسار'), findsOneWidget);
  });
}
