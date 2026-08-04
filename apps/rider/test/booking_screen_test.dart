import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_controller.dart';
import 'package:rider/booking/booking_models.dart';
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

/// A seat tile's tap callback. Invoking it directly exercises the real
/// widget→controller→UI wiring without positional hit-testing (which is
/// unreliable through the page-transition/scaffold layers in a widget test).
/// Returns null when the tile is unavailable — which is how the cap is asserted.
VoidCallback? _seatTileTap(WidgetTester tester, String arabicDigit) {
  return tester
      .widget<GestureDetector>(
        find
            .ancestor(
              of: find.text(arabicDigit),
              matching: find.byType(GestureDetector),
            )
            .first,
      )
      .onTap;
}

void main() {
  testWidgets('seat picker updates the total fare live', (tester) async {
    final c = _controller(price: 6000);
    await tester.pumpWidget(_host(c));

    // Starts at 1 seat. The unit price is ٦٬٠٠٠, so ١٢٬٠٠٠ is unambiguously
    // the running total.
    expect(c.seatCount, 1);
    expect(find.text('١٢٬٠٠٠ د.ع'), findsNothing);

    _seatTileTap(tester, '٢')!();
    await tester.pump();

    // 2 seats → total 12,000 د.ع.
    expect(c.seatCount, 2);
    expect(find.text('١٢٬٠٠٠ د.ع'), findsOneWidget);
    expect(find.text('الإجمالي لـمقعدان'), findsOneWidget);

    _seatTileTap(tester, '١')!();
    await tester.pump();
    expect(c.seatCount, 1);
    expect(find.text('١٢٬٠٠٠ د.ع'), findsNothing);
  });

  testWidgets('seat picker never exceeds available seats', (tester) async {
    final c = _controller(seatsAvailable: 2, price: 6000);
    await tester.pumpWidget(_host(c));

    _seatTileTap(tester, '٢')!(); // 1 → 2 (max)
    await tester.pump();
    expect(c.seatCount, 2);

    // Counts above the cap are rendered but dead — no tap callback at all,
    // which is what makes the ceiling visible instead of merely unreachable.
    expect(_seatTileTap(tester, '٣'), isNull);
    expect(_seatTileTap(tester, '٤'), isNull);
    expect(c.seatCount, 2);
  });

  testWidgets('confirm is disabled until both map points are set',
      (tester) async {
    final c = _controller();
    await tester.pumpWidget(_host(c));
    expect(c.canSubmit, isFalse);
    // Prompts show before any point is chosen.
    expect(find.text('حدّد النقطة على الخريطة'), findsNWidgets(2));

    c.setPickupPoint(
        const GeoPoint(lat: 31.99, lng: 44.31, label: 'حي السلام'));
    await tester.pump();
    expect(c.canSubmit, isFalse); // dropoff still unset

    c.setDropoffPoint(
        const GeoPoint(lat: 32.61, lng: 44.02, label: 'قرب المستشفى'));
    await tester.pump();

    expect(c.canSubmit, isTrue);
    // Chosen labels replace the prompts.
    expect(find.text('حي السلام'), findsOneWidget);
    expect(find.text('قرب المستشفى'), findsOneWidget);
  });

  testWidgets('the total line reads as 3 seats, not 30', (tester) async {
    // `٠` IS a dot, so the old "الإجمالي · ٣ مقاعد" read as "٣٠ مقاعد". It was
    // invisible at 1 and 2 seats, because the Arabic dual ("مقعدان") carries no
    // digit for a separator to fuse with — which is exactly why the golden,
    // fixtured at 2 seats, never caught it.
    final c = _controller(seatsAvailable: 4);
    await tester.pumpWidget(_host(c));

    c.setSeatCount(3);
    await tester.pump();

    expect(find.text('الإجمالي لـ٣ مقاعد'), findsOneWidget);

    final offenders = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
        .toList();
    expect(offenders, isEmpty,
        reason: 'a middle dot touches an Arabic-Indic digit in: $offenders');
  });
}
