import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/trip_detail_controller.dart';
import 'package:driver/trip/trip_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

Widget _host(TripDetailController c) =>
    ChangeNotifierProvider<TripDetailController>.value(
      value: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: TripDetailScreen(),
        ),
      ),
    );

Future<TripDetailController> _loaded(
  FakeDriverTripApi api,
  TripStatus status,
) async {
  final c = TripDetailController(
    api: api,
    trip: tripFixture(status: status, seatsTotal: 4, seatsAvailable: 0),
    corridor: najafKarbala,
  );
  await c.load();
  return c;
}

void main() {
  testWidgets('OPEN: lists each booking (name/pickup/dropoff) + start/cancel',
      (t) async {
    final api = FakeDriverTripApi()
      ..tripBookingsResult = [
        bookingFixture(
          id: 'b1',
          riderName: 'علي حسن',
          pickupLabel: 'كراج النجف',
          dropoffLabel: 'باب القبلة',
        ),
      ];
    final c = await _loaded(api, TripStatus.open);
    await t.pumpWidget(_host(c));
    await t.pump();

    expect(find.text('علي حسن'), findsOneWidget);
    expect(find.textContaining('كراج النجف'), findsOneWidget);
    expect(find.textContaining('باب القبلة'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'ابدأ الرحلة'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'إلغاء الرحلة'), findsOneWidget);
  });

  testWidgets('EN_ROUTE: صعد on a confirmed booking invokes onboard', (t) async {
    final api = FakeDriverTripApi()
      ..tripBookingsResult = [
        bookingFixture(id: 'b1', riderName: 'علي', status: BookingStatus.confirmed),
      ];
    final c = await _loaded(api, TripStatus.enRoute);
    await t.pumpWidget(_host(c));
    await t.pump();

    final onboard = t.widget<AppButton>(find.widgetWithText(AppButton, 'صعد'));
    onboard.onPressed!();
    await t.pump();
    await t.pump();

    expect(api.onboardCalls, ['b1']);
    expect(c.bookings.single.status, BookingStatus.onboard);
  });

  testWidgets('EN_ROUTE bottom action is أنهِ الرحلة (no start/cancel)',
      (t) async {
    final api = FakeDriverTripApi()..tripBookingsResult = [bookingFixture()];
    final c = await _loaded(api, TripStatus.enRoute);
    await t.pumpWidget(_host(c));
    await t.pump();

    expect(find.widgetWithText(AppButton, 'أنهِ الرحلة'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'ابدأ الرحلة'), findsNothing);
  });

  testWidgets('empty bookings shows the no-bookings hint', (t) async {
    final api = FakeDriverTripApi()..tripBookingsResult = const [];
    final c = await _loaded(api, TripStatus.open);
    await t.pumpWidget(_host(c));
    await t.pump();

    expect(find.text('لا توجد حجوزات على هذه الرحلة بعد'), findsOneWidget);
  });
}
