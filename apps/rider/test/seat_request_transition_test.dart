import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/my_bookings_controller.dart';
import 'package:rider/booking/my_bookings_screen.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/pool/seat_request_card.dart';
import 'package:rider/pool/seat_request_models.dart';
import 'package:rider/pool/seat_requests_controller.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';
import 'support/fakes.dart';
import 'support/pool_fakes.dart';

/// **The moment the two systems meet.**
///
/// A claimed pool becomes an ordinary `Trip` with an ordinary `SeatBooking` —
/// rows nothing downstream distinguishes from a driver-posted trip. The rider's
/// screen has to make that read as *one thing becoming another*, on one surface,
/// not as something vanishing here and appearing over there.
///
/// A unit test cannot see this: it is a property of which widgets are on screen
/// after two controllers refresh, so it is driven through the real screen.
class _NullLauncher implements LinkLauncher {
  @override
  Future<bool> open(Uri uri) async => true;
}

void main() {
  /// حجوزاتي with both controllers, exactly as the app shell provides them.
  Future<Widget> screen({
    required List<SeatRequest> requests,
    required List<Booking> bookings,
    FakeSeatRequestApi? requestApi,
    FakeBookingApi? bookingApi,
  }) async {
    // Note the parentheses: `a ?? b..c = d` cascades onto the RESULT of `??`,
    // so without them a caller-supplied fake would have its script overwritten
    // by the defaults it was passed instead of.
    final bApi = bookingApi ??
        (FakeBookingApi()
          ..listMineResult = bookings
          ..driverContactResult =
              contactFixture(name: 'أبو علي', phone: '+9647701234567'));
    final rApi = requestApi ?? (FakeSeatRequestApi()..listMineResult = requests);

    final bookingsController = MyBookingsController(api: bApi);
    final requestsController = SeatRequestsController(api: rApi);
    await bookingsController.load();
    await requestsController.load();
    final auth = await signedInAuth();

    return MultiProvider(
      providers: [
        Provider<LinkLauncher>.value(value: _NullLauncher()),
        ChangeNotifierProvider<MyBookingsController>.value(
            value: bookingsController),
        ChangeNotifierProvider<SeatRequestsController>.value(
            value: requestsController),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: MyBookingsScreen(),
        ),
      ),
    );
  }

  testWidgets(
      'BEFORE the claim: the request is on حجوزاتي, and «لا توجد حجوزات» is NOT',
      (t) async {
    // A rider whose only live thing is a request must not be told they have
    // nothing — the screen would be contradicting the card on it.
    await t.pumpWidget(await screen(
      requests: [seatRequestFixture(stage: SeatRequestStage.waitingForDriver)],
      bookings: const [],
    ));
    await t.pump();

    expect(find.byType(SeatRequestCard), findsOneWidget);
    expect(find.text('بانتظار سائق'), findsOneWidget);
    expect(find.text('لا توجد حجوزات بعد'), findsNothing);
    expect(find.text('لا توجد رحلات قادمة.'), findsNothing);
  });

  testWidgets('AFTER the claim: the request is gone and a NORMAL booking card '
      'is in its place — same screen, same rules', (t) async {
    final rApi = FakeSeatRequestApi()
      ..listMineResult = [
        seatRequestFixture(stage: SeatRequestStage.waitingForDriver),
      ];
    final bApi = FakeBookingApi()
      ..listMineResult = const []
      ..driverContactResult =
          contactFixture(name: 'أبو علي', phone: '+9647701234567');

    await t.pumpWidget(await screen(
      requests: const [],
      bookings: const [],
      requestApi: rApi,
      bookingApi: bApi,
    ));
    await t.pump();
    expect(find.byType(SeatRequestCard), findsOneWidget);

    // The driver claims. Server-side that is one transaction; here it is what
    // the next poll reads back: the request goes CLAIMED (no longer live) and
    // a seat booking exists.
    rApi.listMineResult = [
      seatRequestFixture(
        stage: SeatRequestStage.claimed,
        bookingId: 'b1',
        tripId: 't1',
      ),
    ];
    bApi.listMineResult = [
      mineFixture(
        id: 'b1',
        seatCount: 3,
        fare: 18000,
        status: BookingStatus.confirmed,
        upcoming: true,
      ),
    ];
    await t.pumpAndSettle();
    // The screen's own poll/refresh path: both controllers, one beat.
    await t
        .element(find.byType(MyBookingsScreen))
        .read<SeatRequestsController>()
        .refreshSilently();
    await t
        .element(find.byType(MyBookingsScreen))
        .read<MyBookingsController>()
        .refreshSilently();
    await t.pumpAndSettle();

    // One journey, one card. The request row is gone…
    expect(find.byType(SeatRequestCard), findsNothing);
    // …and what replaced it is the ORDINARY booking card, with everything a
    // driver-posted booking carries: the status badge, the fare, the driver's
    // number, and the same cancel action under the same rules. If any of these
    // were missing, a pooled trip would be a second-class booking — the
    // parallel universe this design exists to avoid.
    expect(find.text('مؤكد'), findsOneWidget);
    expect(find.text(formatPrice(18000)), findsOneWidget);
    expect(find.byType(ContactRow), findsOneWidget);
    expect(find.textContaining('+964'), findsWidgets);
    expect(find.text('إلغاء الحجز'), findsOneWidget);
    expect(find.text('تعديل عدد المقاعد'), findsOneWidget);
  });

  testWidgets('a request with an open raise offers the price sheet, and the '
      'cancel action is NOT offered on it', (t) async {
    // Cancelling a claimed pool goes through the booking rules; the server
    // refuses it here, and an action the server refuses is worse than none.
    await t.pumpWidget(await screen(
      requests: [
        seatRequestFixture(
          stage: SeatRequestStage.raisePending,
          raise: raiseFixture(),
        ),
      ],
      bookings: const [],
    ));
    await t.pump();

    expect(find.text('اطّلع على السعر الجديد'), findsOneWidget);
    expect(find.text('إلغاء الطلب'), findsNothing);
  });

  testWidgets('an unclaimed request CAN be cancelled from here', (t) async {
    await t.pumpWidget(await screen(
      requests: [seatRequestFixture(stage: SeatRequestStage.waitingForRiders)],
      bookings: const [],
    ));
    await t.pump();
    expect(find.text('إلغاء الطلب'), findsOneWidget);
  });

  testWidgets('requests sit under «قادمة» only — a live request is not history',
      (t) async {
    await t.pumpWidget(await screen(
      requests: [seatRequestFixture(stage: SeatRequestStage.waitingForDriver)],
      bookings: [
        mineFixture(
          id: 'b9',
          seatCount: 1,
          fare: 6000,
          status: BookingStatus.completed,
          upcoming: false,
        ),
      ],
    ));
    await t.pump();
    expect(find.byType(SeatRequestCard), findsOneWidget);

    await t.tap(find.textContaining(RegExp('^سابقة')));
    // Past the 120ms AppCard/AppButton cross-fade, twice over.
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));

    expect(find.byType(SeatRequestCard), findsNothing);
  });

  testWidgets('the request sits ABOVE the bookings, not below them', (t) async {
    // Order is the whole mechanism: the claim replaces the row in place, so the
    // rider's eye does not have to travel to find what became of it.
    await t.pumpWidget(await screen(
      requests: [seatRequestFixture(stage: SeatRequestStage.waitingForDriver)],
      bookings: [
        mineFixture(
          id: 'b1',
          seatCount: 1,
          fare: 6000,
          status: BookingStatus.confirmed,
          upcoming: true,
        ),
      ],
    ));
    await t.pump();

    final requestY = t.getTopLeft(find.byType(SeatRequestCard)).dy;
    final bookingY = t.getTopLeft(find.text('مؤكد')).dy;
    expect(requestY, lessThan(bookingY));
  });
}
