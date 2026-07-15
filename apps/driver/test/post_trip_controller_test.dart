import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/post_trip_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

PostTripController _controller(FakeDriverTripApi api, {int maxSeats = 4}) =>
    PostTripController(api: api, maxSeats: maxSeats);

void main() {
  group('PostTripController', () {
    test('loadCorridors filters inactive corridors and default-selects first',
        () async {
      final api = FakeDriverTripApi()
        ..corridors = const [
          najafKarbala,
          karbalaNajaf,
          Corridor(
            id: 'c3',
            originCity: 'X',
            destCity: 'Y',
            active: false,
            pricePerSeat: 1000,
          ),
        ];
      final c = _controller(api);
      await c.loadCorridors();
      expect(c.corridorsLoad, CorridorsLoad.ready);
      expect(c.corridors.length, 2); // inactive filtered out
      expect(c.corridor, najafKarbala);
      expect(c.pricePerSeat, 6000);
    });

    test('swapDirection selects the reverse corridor', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala, karbalaNajaf];
      final c = _controller(api);
      await c.loadCorridors();
      c.swapDirection();
      expect(c.corridor, karbalaNajaf);
    });

    test('seat count is capped at the vehicle seats', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api, maxSeats: 3);
      await c.loadCorridors();
      expect(c.seatCount, 1);
      c.incrementSeat();
      c.incrementSeat();
      expect(c.seatCount, 3);
      c.incrementSeat(); // capped
      expect(c.seatCount, 3);
      expect(c.canIncrement, isFalse);
      c.setSeatCount(99);
      expect(c.seatCount, 3);
    });

    test('submit (الآن) sends departNow=true and no departureTime', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api, maxSeats: 4);
      await c.loadCorridors();
      c.setSeatCount(2);
      expect(c.mode, DepartMode.now);
      expect(c.canSubmit, isTrue);

      final ok = await c.submit();

      expect(ok, isTrue);
      expect(api.postCalls, 1);
      expect(api.lastDepartNow, isTrue);
      expect(api.lastDepartureTime, isNull);
      expect(api.lastSeatsTotal, 2);
      expect(api.lastCorridorId, 'c1');
      expect(c.posted, isNotNull);
    });

    test('scheduled needs a chosen time; then sends departureTime', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();
      c.setMode(DepartMode.scheduled);
      expect(c.canSubmit, isFalse); // no time chosen yet

      c.setScheduledAt(DateTime.utc(2026, 7, 20, 10, 0));
      expect(c.canSubmit, isTrue);

      final ok = await c.submit();
      expect(ok, isTrue);
      expect(api.lastDepartNow, isFalse);
      expect(api.lastDepartureTime, isNotNull);
    });

    test('trip type defaults to general and is sent on submit', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();
      expect(c.tripType, TripType.general);

      await c.submit();
      expect(api.lastTripType, TripType.general);
    });

    test('setTripType(womenFamily) is sent on submit', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();

      c.setTripType(TripType.womenFamily);
      expect(c.tripType, TripType.womenFamily);

      final ok = await c.submit();
      expect(ok, isTrue);
      expect(api.lastTripType, TripType.womenFamily);
    });

    test('submit error surfaces the backend message', () async {
      final api = FakeDriverTripApi()
        ..corridors = const [najafKarbala]
        ..postError = const ApiException(
          'يجب اعتماد حسابك كسائق قبل إعلان الرحلات.',
          statusCode: 403,
        );
      final c = _controller(api);
      await c.loadCorridors();
      final ok = await c.submit();
      expect(ok, isFalse);
      expect(c.error, contains('اعتماد حسابك'));
    });
  });
}
