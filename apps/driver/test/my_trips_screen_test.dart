import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/my_trips_controller.dart';
import 'package:driver/trip/my_trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

/// رحلاتي, with attention to the «الآن» validity window.
///
/// A departNow trip is live for a limited time and then stops being findable by
/// riders. Until this screen said so, the driver had no way to tell whether the
/// trip they just posted was still catchable — the card showed a departure time
/// of "now" and nothing else, which is indistinguishable from a trip whose
/// window shut twenty minutes ago.
void main() {
  Future<Widget> host(List<DriverTrip> trips) async {
    final api = FakeDriverTripApi()
      ..corridors = const [najafKarbala, karbalaNajaf]
      ..myTripsResult = trips;
    final c = MyTripsController(api: api);
    await c.load();
    return ChangeNotifierProvider<MyTripsController>.value(
      value: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: MyTripsScreen(),
        ),
      ),
    );
  }

  testWidgets('an open «الآن» trip says how long riders can still catch it',
      (tester) async {
    // Posted 04:30 UTC with a 30-minute window → catchable until 05:00 UTC,
    // which is 08:00 Baghdad (formatTime shifts by +3).
    await tester.pumpWidget(await host([
      tripFixture(id: 't1', hourUtc: 4, minute: 30, departNow: true),
    ]));

    expect(find.textContaining('متاحة للحجز حتى الساعة'), findsOneWidget);
    expect(find.textContaining('٠٨:٠٠'), findsOneWidget);
  });

  testWidgets('a SCHEDULED trip shows no window — its departure time is the whole story',
      (tester) async {
    await tester.pumpWidget(await host([
      tripFixture(id: 't1', hourUtc: 4, minute: 30, departNow: false),
    ]));

    expect(find.textContaining('متاحة للحجز حتى'), findsNothing);
  });

  testWidgets('a «الآن» trip that is no longer OPEN shows no window',
      (tester) async {
    // Once it is LOCKED (or cancelled by the expiry sweep) it takes no more
    // bookings whatever the clock says, so a window would be a lie.
    await tester.pumpWidget(await host([
      tripFixture(
        id: 't1',
        hourUtc: 4,
        minute: 30,
        departNow: true,
        status: TripStatus.locked,
      ),
    ]));

    expect(find.textContaining('متاحة للحجز حتى'), findsNothing);
  });

  testWidgets('shows the window only on the «الآن» trip in a mixed list',
      (tester) async {
    await tester.pumpWidget(await host([
      tripFixture(id: 't1', corridorId: 'c1', hourUtc: 4, minute: 30, departNow: true),
      tripFixture(id: 't2', corridorId: 'c2', hourUtc: 6, minute: 0, departNow: false),
      tripFixture(id: 't3', corridorId: 'c1', hourUtc: 7, minute: 15, departNow: false),
    ]));

    expect(find.textContaining('متاحة للحجز حتى الساعة'), findsOneWidget);
  });

  testWidgets('never puts a dot beside an Arabic-Indic numeral', (tester) async {
    // The standing rule: `٠` IS a dot, so a separator next to a digit run reads
    // as an extra zero. The window badge renders a zero-padded clock («٠٨:٠٠»),
    // which is exactly the shape that goes wrong — hence «الساعة» between the
    // words and the digits rather than a middle dot. Seat count is 3, because
    // formatSeats returns the Arabic dual at 2 and carries no digit at all.
    await tester.pumpWidget(await host([
      tripFixture(
        id: 't1',
        hourUtc: 4,
        minute: 30,
        departNow: true,
        seatsTotal: 4,
        seatsAvailable: 3,
      ),
    ]));

    final offenders = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
        .toList();

    expect(offenders, isEmpty,
        reason: 'a middle dot touches an Arabic-Indic digit in رحلاتي');
  });
}
