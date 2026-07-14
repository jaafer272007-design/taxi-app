import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rider/booking/booking_controller.dart';
import 'package:rider/booking/booking_error.dart';
import 'package:rider/core/api_exception.dart';

import 'support/booking_fakes.dart';
import 'support/trip_fakes.dart';

BookingController _controller(
  FakeBookingApi api, {
  int seatsAvailable = 3,
  int price = 6000,
}) {
  return BookingController(
    api: api,
    trip: tripFixture(seatsAvailable: seatsAvailable, price: price),
    originCity: 'Najaf',
    destCity: 'Karbala',
  );
}

void main() {
  group('BookingController', () {
    test('seat count is bounded to 1..min(4, seatsAvailable) and drives fare',
        () {
      final c = _controller(FakeBookingApi(), seatsAvailable: 2, price: 6000);
      expect(c.seatCount, 1);
      expect(c.fare, 6000);
      expect(c.maxSeats, 2);

      c.incrementSeat();
      expect(c.seatCount, 2);
      expect(c.fare, 12000);

      c.incrementSeat(); // capped at 2 available
      expect(c.seatCount, 2);
      expect(c.canIncrement, isFalse);

      c.decrementSeat();
      c.decrementSeat(); // capped at 1
      expect(c.seatCount, 1);
      expect(c.canDecrement, isFalse);
    });

    test('caps at 4 even when more seats are available', () {
      final c = _controller(FakeBookingApi(), seatsAvailable: 6);
      expect(c.maxSeats, 4);
      c
        ..setSeatCount(10);
      expect(c.seatCount, 4);
    });

    test('canSubmit requires both pickup and dropoff labels', () {
      final c = _controller(FakeBookingApi());
      expect(c.canSubmit, isFalse);
      c.setPickupLabel('حي السلام');
      expect(c.canSubmit, isFalse);
      c.setDropoffLabel('قرب المستشفى');
      expect(c.canSubmit, isTrue);
    });

    test('submit posts the booking and stores the result', () async {
      final api = FakeBookingApi();
      final c = _controller(api)
        ..setPickupLabel('حي السلام')
        ..setDropoffLabel('قرب المستشفى')
        ..setSeatCount(2);

      final ok = await c.submit();

      expect(ok, isTrue);
      expect(api.createCalls, 1);
      expect(api.lastSeatCount, 2);
      expect(c.result, isNotNull);
      expect(c.error, isNull);
      expect(c.submitting, isFalse);
    });

    test('double-submit is prevented while a booking is in flight', () async {
      final gate = Completer<void>();
      final api = FakeBookingApi()..createGate = gate;
      final c = _controller(api)
        ..setPickupLabel('حي السلام')
        ..setDropoffLabel('قرب المستشفى');

      final first = c.submit(); // reaches the awaited create and parks there
      expect(c.submitting, isTrue);

      final second = await c.submit(); // guarded — returns immediately
      expect(second, isFalse);

      gate.complete();
      expect(await first, isTrue);
      expect(api.createCalls, 1);
    });

    test('409 seat-taken maps to a seatGone error', () async {
      final api = FakeBookingApi()
        ..createError = const ApiException('لم يعد المقعد متاحاً.', statusCode: 409);
      final c = _controller(api, seatsAvailable: 1)
        ..setPickupLabel('حي السلام')
        ..setDropoffLabel('قرب المستشفى');

      final ok = await c.submit();

      expect(ok, isFalse);
      expect(c.result, isNull);
      expect(c.error?.kind, BookingErrorKind.seatGone);
      expect(c.error?.message, contains('تم حجزه للتو'));
      expect(c.submitting, isFalse);
    });
  });
}
