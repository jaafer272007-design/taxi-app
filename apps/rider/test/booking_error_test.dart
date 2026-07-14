import 'package:flutter_test/flutter_test.dart';
import 'package:rider/booking/booking_error.dart';
import 'package:shared/shared.dart';

void main() {
  group('classifyBookingError', () {
    test('409 race (لم يعد المقعد) → seatGone with friendly copy', () {
      final e = classifyBookingError(
        const ApiException('لم يعد المقعد متاحاً.', statusCode: 409),
      );
      expect(e.kind, BookingErrorKind.seatGone);
      expect(e.message, contains('تم حجزه للتو'));
    });

    test('409 pre-check (المقاعد المطلوبة غير متاحة) → seatGone', () {
      final e = classifyBookingError(
        const ApiException('المقاعد المطلوبة غير متاحة.', statusCode: 409),
      );
      expect(e.kind, BookingErrorKind.seatGone);
    });

    test('409 trip not open → tripClosed, keeps backend message', () {
      final e = classifyBookingError(
        const ApiException('الرحلة غير متاحة للحجز.', statusCode: 409),
      );
      expect(e.kind, BookingErrorKind.tripClosed);
      expect(e.message, 'الرحلة غير متاحة للحجز.');
    });

    test('400 own trip → invalid, keeps backend message', () {
      final e = classifyBookingError(
        const ApiException('لا يمكنك حجز رحلتك الخاصة.', statusCode: 400),
      );
      expect(e.kind, BookingErrorKind.invalid);
      expect(e.message, 'لا يمكنك حجز رحلتك الخاصة.');
    });

    test('404 → tripClosed', () {
      final e = classifyBookingError(
        const ApiException('الرحلة غير موجودة.', statusCode: 404),
      );
      expect(e.kind, BookingErrorKind.tripClosed);
    });

    test('network → network (retryable)', () {
      final e = classifyBookingError(
        const ApiException('تعذّر الاتصال بالخادم.', isNetwork: true),
      );
      expect(e.kind, BookingErrorKind.network);
    });

    test('unmapped status → generic', () {
      final e = classifyBookingError(
        const ApiException('خطأ.', statusCode: 500),
      );
      expect(e.kind, BookingErrorKind.generic);
    });
  });
}
