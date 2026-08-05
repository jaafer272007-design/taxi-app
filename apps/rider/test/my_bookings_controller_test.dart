import 'package:flutter_test/flutter_test.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/booking/my_bookings_controller.dart';

import 'support/booking_fakes.dart';
import 'package:shared/shared.dart';

void main() {
  group('MyBookingsController', () {
    test('load groups bookings into upcoming vs past', () async {
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(id: 'b1', upcoming: true),
          mineFixture(id: 'b2', upcoming: false, status: BookingStatus.completed),
          mineFixture(id: 'b3', upcoming: true),
        ];
      final c = MyBookingsController(api: api);

      await c.load();

      expect(c.status, MyBookingsStatus.loaded);
      expect(c.upcoming.map((b) => b.id), ['b1', 'b3']);
      expect(c.past.map((b) => b.id), ['b2']);
      expect(c.hasLoaded, isTrue);
    });

    test('canCancel only for upcoming CONFIRMED bookings', () {
      final c = MyBookingsController(api: FakeBookingApi());
      expect(c.canCancel(mineFixture(upcoming: true, status: BookingStatus.confirmed)),
          isTrue);
      expect(c.canCancel(mineFixture(upcoming: false, status: BookingStatus.confirmed)),
          isFalse);
      expect(c.canCancel(mineFixture(upcoming: true, status: BookingStatus.completed)),
          isFalse);
    });

    test('cancel flips the booking to CANCELLED on success', () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)]
        ..cancelResult = bookingFixture(id: 'b1', status: BookingStatus.cancelled);
      final c = MyBookingsController(api: api);
      await c.load();

      final err = await c.cancel('b1');

      expect(err, isNull);
      expect(api.cancelCalls, 1);
      expect(c.upcoming.single.status, BookingStatus.cancelled);
    });

    test('cancel past the cutoff returns the Arabic error, status unchanged',
        () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)]
        ..cancelError = const ApiException(
          'فات وقت الإلغاء المجاني (قبل 15 دقيقة من المغادرة).',
          statusCode: 409,
        );
      final c = MyBookingsController(api: api);
      await c.load();

      final err = await c.cancel('b1');

      expect(err, contains('فات وقت الإلغاء'));
      expect(c.upcoming.single.status, BookingStatus.confirmed);
    });
  });

  group('background refresh (poll + pull-to-refresh)', () {
    test('a failed refresh keeps the bookings and says nothing', () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)];
      final c = MyBookingsController(api: api);
      await c.load();

      api.listMineError = const ApiException('لا يوجد اتصال بالإنترنت.');
      await c.refreshSilently();

      expect(c.status, MyBookingsStatus.loaded);
      expect(c.upcoming.map((b) => b.id), ['b1']);
      expect(c.error, isNull);
    });

    test('a refresh never shows the loading state', () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)];
      final c = MyBookingsController(api: api);
      await c.load();

      final seen = <MyBookingsStatus>[];
      c.addListener(() => seen.add(c.status));
      await c.refreshSilently();

      expect(seen, isNot(contains(MyBookingsStatus.loading)));
    });

    test('a refresh picks up a driver-side status change', () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)];
      final c = MyBookingsController(api: api);
      await c.load();
      expect(c.upcoming.single.status, BookingStatus.confirmed);

      // The driver cancelled from their side.
      api.listMineResult = [
        mineFixture(id: 'b1', upcoming: true, status: BookingStatus.cancelled),
      ];
      await c.refreshSilently();

      expect(c.upcoming.single.status, BookingStatus.cancelled);
    });

    test('a visible load still surfaces its error', () async {
      final api = FakeBookingApi()
        ..listMineError = const ApiException('لا يوجد اتصال بالإنترنت.');
      final c = MyBookingsController(api: api);

      await c.load();

      expect(c.status, MyBookingsStatus.error);
      expect(c.error, 'لا يوجد اتصال بالإنترنت.');
    });
  });

  group('hasLiveBookings (whether this screen polls at all)', () {
    Future<MyBookingsController> withBookings(List<Booking> bookings) async {
      final api = FakeBookingApi()..listMineResult = bookings;
      final c = MyBookingsController(api: api);
      await c.load();
      return c;
    }

    test('an empty list is not live', () async {
      expect((await withBookings(const [])).hasLiveBookings, isFalse);
    });

    test('an upcoming CONFIRMED booking is live', () async {
      final c = await withBookings([mineFixture(id: 'b1', upcoming: true)]);
      expect(c.hasLiveBookings, isTrue);
    });

    test('a finished history is not live', () async {
      final c = await withBookings([
        mineFixture(
            id: 'b1', upcoming: false, status: BookingStatus.completed),
        mineFixture(
            id: 'b2', upcoming: false, status: BookingStatus.cancelled),
      ]);
      expect(c.hasLiveBookings, isFalse,
          reason: 'asking the server about settled trips forever');
    });

    test('an upcoming booking the rider cancelled is not live', () async {
      final c = await withBookings([
        mineFixture(id: 'b1', upcoming: true, status: BookingStatus.cancelled),
      ]);
      expect(c.hasLiveBookings, isFalse);
    });

    test('one live booking among finished ones is enough', () async {
      final c = await withBookings([
        mineFixture(
            id: 'b1', upcoming: false, status: BookingStatus.completed),
        mineFixture(id: 'b2', upcoming: true),
      ]);
      expect(c.hasLiveBookings, isTrue);
    });
  });

  group('BUG 1 — the bucket follows STATUS, not the clock', () {
    // The server decides; the controller must not second-guess it. These pin
    // that the app files a booking exactly where `upcoming` says, so the rule
    // stays in one place (booking-lifecycle.ts) rather than two.

    test('a COMPLETED booking flagged past lands in سابقة, not قادمة', () async {
      // The reported bug, from the app's side: departure is still ahead — the
      // fixture's trip is at a fixed future-ish clock — but the ride is done.
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(
            id: 'b1',
            status: BookingStatus.completed,
            upcoming: false,
          ),
        ];
      final c = MyBookingsController(api: api);
      await c.load();

      expect(c.past.map((b) => b.id), ['b1']);
      expect(c.upcoming, isEmpty);
    });

    test('a live booking still lands in قادمة — the fix is narrow', () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)];
      final c = MyBookingsController(api: api);
      await c.load();

      expect(c.upcoming.map((b) => b.id), ['b1']);
      expect(c.past, isEmpty);
    });

    test('cancelling moves the card out of قادمة straight away', () async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)]
        ..cancelResult = bookingFixture(id: 'b1', status: BookingStatus.cancelled);
      final c = MyBookingsController(api: api);
      await c.load();

      await c.cancel('b1');

      // Without this the rider watches a cancelled seat sit under «قادمة»
      // until the next refresh.
      expect(c.upcoming, isEmpty);
      expect(c.past.single.status, BookingStatus.cancelled);
    });
  });

  group('BUG 2 — the rider rates the driver', () {
    FakeBookingApi apiWithRatable() => FakeBookingApi()
      ..listMineResult = [
        mineFixture(
          id: 'b1',
          status: BookingStatus.completed,
          upcoming: false,
          ratable: true,
          driverUserId: 'du1',
        ),
      ];

    test('a completed unrated ride is awaiting a rating', () async {
      final c = MyBookingsController(api: apiWithRatable());
      await c.load();

      expect(c.awaitingRating.map((b) => b.id), ['b1']);
      expect(c.past.single.canRate, isTrue);
    });

    test('rating posts the trip, the driver and the score', () async {
      final api = apiWithRatable();
      final c = MyBookingsController(api: api);
      await c.load();

      final err = await c.rateDriver(bookingId: 'b1', score: 5, comment: 'ممتاز');

      expect(err, isNull);
      expect(api.rateCalls.single.tripId, 't-b1');
      expect(api.rateCalls.single.toUserId, 'du1');
      expect(api.rateCalls.single.score, 5);
    });

    test('once rated the action disappears', () async {
      final c = MyBookingsController(api: apiWithRatable());
      await c.load();

      await c.rateDriver(bookingId: 'b1', score: 4);

      expect(c.awaitingRating, isEmpty);
      expect(c.past.single.canRate, isFalse);
      expect(c.past.single.ratedDriver, isTrue);
    });

    test('a 409 is idempotent success — the rating already exists', () async {
      // Matches the driver side. A double-tap, or a retry after a dropped
      // response, has already achieved what the caller wanted; reporting an
      // error for finished work would leave the sheet open on a lie.
      final api = apiWithRatable()
        ..rateError = const ApiException('قيّمت هذا الشخص مسبقاً.', statusCode: 409);
      final c = MyBookingsController(api: api);
      await c.load();

      final err = await c.rateDriver(bookingId: 'b1', score: 3);

      expect(err, isNull);
      expect(c.past.single.ratedDriver, isTrue);
    });

    test('a real failure surfaces its Arabic message and keeps the action',
        () async {
      final api = apiWithRatable()
        ..rateError = const ApiException('لا يوجد اتصال بالإنترنت.', isNetwork: true);
      final c = MyBookingsController(api: api);
      await c.load();

      final err = await c.rateDriver(bookingId: 'b1', score: 3);

      expect(err, 'لا يوجد اتصال بالإنترنت.');
      expect(c.past.single.canRate, isTrue, reason: 'they can try again');
    });

    test('two bookings on ONE trip are rated together', () async {
      // A rating is per (trip, driver). Marking only the tapped booking would
      // leave a second «قيّم السائق» on the same trip that the server answers
      // 409 to — an action that exists only to fail.
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(
              id: 'b1',
              tripId: 't-shared',
              status: BookingStatus.completed,
              upcoming: false,
              ratable: true),
          mineFixture(
              id: 'b2',
              tripId: 't-shared',
              status: BookingStatus.completed,
              upcoming: false,
              ratable: true),
        ];
      final c = MyBookingsController(api: api);
      await c.load();
      expect(c.awaitingRating, hasLength(2));

      await c.rateDriver(bookingId: 'b1', score: 5);

      expect(c.awaitingRating, isEmpty);
      expect(api.rateCalls, hasLength(1), reason: 'one trip, one rating');
    });

    test('bookings on DIFFERENT trips stay independently ratable', () async {
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(id: 'b1', status: BookingStatus.completed, upcoming: false, ratable: true),
          mineFixture(id: 'b2', status: BookingStatus.completed, upcoming: false, ratable: true),
        ];
      final c = MyBookingsController(api: api);
      await c.load();

      await c.rateDriver(bookingId: 'b1', score: 5);

      expect(c.awaitingRating.map((b) => b.id), ['b2']);
    });

    test('a ride that never happened is not ratable', () async {
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(
            id: 'b1',
            status: BookingStatus.cancelled,
            upcoming: false,
            ratable: false,
          ),
        ];
      final c = MyBookingsController(api: api);
      await c.load();

      expect(c.awaitingRating, isEmpty);
      expect(c.past.single.canRate, isFalse);
    });

    test('a booking with no driver id cannot be rated', () async {
      // An older API, or a response that omitted the trip. Better to draw no
      // action than one that cannot address itself to anyone.
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(
            id: 'b1',
            status: BookingStatus.completed,
            upcoming: false,
            ratable: true,
            driverUserId: null,
          ),
        ];
      final c = MyBookingsController(api: api);
      await c.load();

      expect(c.past.single.canRate, isFalse);
      expect(await c.rateDriver(bookingId: 'b1', score: 5), isNotNull);
      expect(api.rateCalls, isEmpty);
    });
  });
}
