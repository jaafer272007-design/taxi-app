import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_controller.dart';
import 'package:rider/booking/booking_screen.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';
import 'support/trip_fakes.dart';

BookingController _controller({int seatsAvailable = 3, int price = 6000}) {
  return BookingController(
    api: FakeBookingApi(),
    trip: tripFixture(seatsAvailable: seatsAvailable, price: price),
    originCity: 'Najaf',
    destCity: 'Karbala',
  );
}

Widget _host(BookingController c) => ChangeNotifierProvider<BookingController>.value(
      value: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: BookingScreen(),
        ),
      ),
    );

/// The stepper button ([icon])'s tap callback. Invoking it directly exercises
/// the real widget→controller→UI wiring without positional hit-testing (which is
/// unreliable through the page-transition/scaffold layers in a widget test).
VoidCallback? _stepButtonTap(WidgetTester tester, IconData icon) {
  return tester
      .widget<GestureDetector>(
        find
            .ancestor(
              of: find.byIcon(icon),
              matching: find.byType(GestureDetector),
            )
            .first,
      )
      .onTap;
}

void main() {
  testWidgets('seat stepper updates the total fare live', (tester) async {
    await tester.pumpWidget(_host(_controller(price: 6000)));

    // Starts at 1 seat → total 6,000; no 12,000 yet.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('12,000 د.ع'), findsNothing);

    _stepButtonTap(tester, AppIcons.plus)!();
    await tester.pump();

    // 2 seats → total 12,000 د.ع.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('12,000 د.ع'), findsOneWidget);

    _stepButtonTap(tester, AppIcons.minus)!();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('12,000 د.ع'), findsNothing);
  });

  testWidgets('seat stepper never exceeds available seats', (tester) async {
    final c = _controller(seatsAvailable: 2, price: 6000);
    await tester.pumpWidget(_host(c));

    _stepButtonTap(tester, AppIcons.plus)!(); // 1 → 2 (max)
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(c.seatCount, 2);

    // At the cap the increment button is disabled (no onTap).
    expect(_stepButtonTap(tester, AppIcons.plus), isNull);
    expect(c.seatCount, 2);
  });

  testWidgets('confirm is disabled until both points are filled',
      (tester) async {
    final c = _controller();
    await tester.pumpWidget(_host(c));
    expect(c.canSubmit, isFalse);

    await tester.enterText(find.byType(TextField).at(0), 'حي السلام');
    await tester.enterText(find.byType(TextField).at(1), 'قرب المستشفى');
    await tester.pump();

    expect(c.canSubmit, isTrue);
  });
}
