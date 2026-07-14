import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/trip_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

TripDetailController _ctrl(FakeDriverTripApi api, DriverTrip trip) =>
    TripDetailController(api: api, trip: trip, corridor: najafKarbala);

void main() {
  group('load', () {
    test('populates bookings and reaches loaded', () async {
      final api = FakeDriverTripApi()
        ..tripBookingsResult = [bookingFixture(id: 'b1', riderName: 'علي')];
      final c = _ctrl(api, tripFixture(status: TripStatus.enRoute));
      await c.load();

      expect(c.loadStatus, TripDetailStatus.loaded);
      expect(c.hasLoaded, isTrue);
      expect(c.bookings.single.riderName, 'علي');
      expect(c.isEmpty, isFalse);
    });

    test('surfaces an API error as the load error message', () async {
      final api = FakeDriverTripApi()
        ..tripBookingsError = const ApiException('غير مصرّح.', statusCode: 403);
      final c = _ctrl(api, tripFixture());
      await c.load();

      expect(c.loadStatus, TripDetailStatus.error);
      expect(c.error, 'غير مصرّح.');
    });
  });

  group('lifecycle gating', () {
    test('canStart / canCancel only for OPEN or LOCKED', () {
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.open)).canStart, isTrue);
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.locked)).canStart, isTrue);
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.enRoute)).canStart, isFalse);
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.settled)).canStart, isFalse);
    });

    test('isEnRoute / isDone reflect status', () {
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.enRoute)).isEnRoute, isTrue);
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.settled)).isDone, isTrue);
      expect(_ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.completed)).isDone, isTrue);
    });

    test('canTransition only while EN_ROUTE and booking still CONFIRMED', () {
      final enRoute = _ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.enRoute));
      expect(enRoute.canTransition(bookingFixture(status: BookingStatus.confirmed)), isTrue);
      expect(enRoute.canTransition(bookingFixture(status: BookingStatus.onboard)), isFalse);

      final open = _ctrl(FakeDriverTripApi(), tripFixture(status: TripStatus.open));
      expect(open.canTransition(bookingFixture(status: BookingStatus.confirmed)), isFalse);
    });
  });

  group('start / cancel', () {
    test('start flips OPEN → EN_ROUTE, calls the API, marks changed', () async {
      final api = FakeDriverTripApi();
      final c = _ctrl(api, tripFixture(status: TripStatus.open));
      await c.load();

      final err = await c.start();

      expect(err, isNull);
      expect(api.startCalls, 1);
      expect(c.status, TripStatus.enRoute);
      expect(c.changed, isTrue);
    });

    test('start returns the backend 409 Arabic message and keeps the status',
        () async {
      final api = FakeDriverTripApi()
        ..startError =
            const ApiException('لا يمكن بدء الرحلة بحالتها الحالية.', statusCode: 409);
      final c = _ctrl(api, tripFixture(status: TripStatus.open));
      await c.load();

      final err = await c.start();

      expect(err, 'لا يمكن بدء الرحلة بحالتها الحالية.');
      expect(c.status, TripStatus.open);
      expect(c.changed, isFalse);
    });

    test('cancel flips OPEN → CANCELLED', () async {
      final api = FakeDriverTripApi();
      final c = _ctrl(api, tripFixture(status: TripStatus.open));
      await c.load();

      final err = await c.cancel();

      expect(err, isNull);
      expect(api.cancelCalls, 1);
      expect(c.status, TripStatus.cancelled);
    });
  });

  group('onboard / no-show update the pill locally', () {
    test('onboard sets that booking to ONBOARD', () async {
      final api = FakeDriverTripApi()
        ..tripBookingsResult = [
          bookingFixture(id: 'b1', status: BookingStatus.confirmed),
          bookingFixture(id: 'b2', status: BookingStatus.confirmed),
        ];
      final c = _ctrl(api, tripFixture(status: TripStatus.enRoute));
      await c.load();

      final err = await c.onboard('b1');

      expect(err, isNull);
      expect(api.onboardCalls, ['b1']);
      expect(c.bookings.firstWhere((b) => b.id == 'b1').status,
          BookingStatus.onboard);
      expect(c.bookings.firstWhere((b) => b.id == 'b2').status,
          BookingStatus.confirmed);
    });

    test('no-show sets that booking to NO_SHOW', () async {
      final api = FakeDriverTripApi()
        ..tripBookingsResult = [bookingFixture(id: 'b1')];
      final c = _ctrl(api, tripFixture(status: TripStatus.enRoute));
      await c.load();

      await c.noShow('b1');

      expect(api.noShowCalls, ['b1']);
      expect(c.bookings.single.status, BookingStatus.noShow);
    });

    test('a failed transition leaves the booking unchanged', () async {
      final api = FakeDriverTripApi()
        ..tripBookingsResult = [bookingFixture(id: 'b1')]
        ..onboardError =
            const ApiException('يجب أن تكون الرحلة جارية (EN_ROUTE).', statusCode: 409);
      final c = _ctrl(api, tripFixture(status: TripStatus.enRoute));
      await c.load();

      final err = await c.onboard('b1');

      expect(err, 'يجب أن تكون الرحلة جارية (EN_ROUTE).');
      expect(c.bookings.single.status, BookingStatus.confirmed);
    });
  });

  group('complete', () {
    test('settles → SETTLED with a summary of seats ridden + cash collected',
        () async {
      final api = FakeDriverTripApi()
        ..tripBookingsResult = [
          bookingFixture(id: 'b1', seatCount: 2, fare: 12000, status: BookingStatus.onboard),
          bookingFixture(id: 'b2', seatCount: 1, fare: 6000, status: BookingStatus.confirmed),
          bookingFixture(id: 'b3', seatCount: 1, fare: 6000, status: BookingStatus.noShow),
        ]
        ..settledBookingsResult = [
          bookingFixture(id: 'b1', riderId: 'r1', seatCount: 2, fare: 12000, status: BookingStatus.completed),
          bookingFixture(id: 'b2', riderId: 'r2', seatCount: 1, fare: 6000, status: BookingStatus.completed),
          bookingFixture(id: 'b3', riderId: 'r3', seatCount: 1, fare: 6000, status: BookingStatus.noShow),
        ];
      final c = _ctrl(api, tripFixture(status: TripStatus.enRoute));
      await c.load();

      final err = await c.complete();

      expect(err, isNull);
      expect(api.completeCalls, 1);
      expect(c.status, TripStatus.settled);
      expect(c.isDone, isTrue);
      expect(c.summary, isNotNull);
      expect(c.summary!.ridersCount, 2);
      expect(c.summary!.seatsRidden, 3); // 2 + 1
      expect(c.summary!.cashCollected, 18000); // 12000 + 6000, NO_SHOW excluded
      // Ridden riders (COMPLETED) become the rating targets, deduped.
      expect(c.riddenRiders.map((b) => b.riderId), ['r1', 'r2']);
    });

    test('surfaces a 409 when the trip is not EN_ROUTE', () async {
      final api = FakeDriverTripApi()
        ..completeError = const ApiException(
            'لا يمكن إكمال الرحلة إلا وهي جارية (EN_ROUTE).',
            statusCode: 409);
      final c = _ctrl(api, tripFixture(status: TripStatus.enRoute));
      await c.load();

      final err = await c.complete();

      expect(err, 'لا يمكن إكمال الرحلة إلا وهي جارية (EN_ROUTE).');
      expect(c.summary, isNull);
    });
  });

  group('rating dedupe', () {
    test('a successful rating marks the rider rated (hides the action)', () async {
      final api = FakeDriverTripApi();
      final c = _ctrl(api, tripFixture(status: TripStatus.settled));

      expect(c.isRated('r1'), isFalse);
      final err = await c.rateRider(riderId: 'r1', score: 5, comment: 'ممتاز');

      expect(err, isNull);
      expect(api.rateCalls, 1);
      expect(api.lastRateRiderId, 'r1');
      expect(api.lastRateScore, 5);
      expect(api.lastRateComment, 'ممتاز');
      expect(c.isRated('r1'), isTrue);
    });

    test('a 409 (already rated) is idempotent: no error, rider marked rated',
        () async {
      final api = FakeDriverTripApi()
        ..rateError = const ApiException(
            'قيّمت هذا الشخص مسبقاً لهذه الرحلة.',
            statusCode: 409);
      final c = _ctrl(api, tripFixture(status: TripStatus.settled));

      final err = await c.rateRider(riderId: 'r1', score: 4);

      expect(err, isNull); // treated as success so the sheet closes cleanly
      expect(c.isRated('r1'), isTrue);
    });

    test('a non-409 error does NOT mark the rider rated', () async {
      final api = FakeDriverTripApi()
        ..rateError = const ApiException('تعذّر الاتصال.', isNetwork: true);
      final c = _ctrl(api, tripFixture(status: TripStatus.settled));

      final err = await c.rateRider(riderId: 'r1', score: 4);

      expect(err, 'تعذّر الاتصال.');
      expect(c.isRated('r1'), isFalse);
    });
  });
}
