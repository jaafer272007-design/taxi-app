import 'package:flutter_test/flutter_test.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/booking/my_bookings_controller.dart';
import 'package:rider/core/api_exception.dart';

import 'support/booking_fakes.dart';

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
}
