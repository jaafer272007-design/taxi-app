import 'package:shared/shared.dart';

/// How a failed booking should be presented, so the UI can offer the right
/// recovery (go back and refresh vs. retry vs. just show the message).
enum BookingErrorKind {
  /// The seat was taken between search and confirm — go back and refresh.
  seatGone,

  /// The trip is no longer bookable (locked, departed, cancelled, or gone).
  tripClosed,

  /// The request itself was rejected (e.g. booking your own trip).
  invalid,

  /// The rider isn't eligible for this trip (e.g. a women/family trip that only
  /// accepts female riders). Not retryable — the trip simply isn't for them.
  notEligible,

  /// Never reached the server — retryable.
  network,

  /// Anything else.
  generic,
}

/// A classified, ready-to-show booking error.
class BookingError {
  const BookingError(this.kind, this.message);

  final BookingErrorKind kind;

  /// Arabic, user-facing.
  final String message;
}

/// Classify a mapped [ApiException] from the booking endpoints into a
/// [BookingError]. The backend already returns clear Arabic messages; this adds
/// the seat-taken race case its own friendly copy and tags each error so the UI
/// can pick the right recovery action. Pure, so it is unit-testable.
BookingError classifyBookingError(ApiException e) {
  if (e.isNetwork) {
    return BookingError(BookingErrorKind.network, e.message);
  }

  final msg = e.message;
  switch (e.statusCode) {
    case 409:
      // The race (`لم يعد المقعد متاحاً`) and the pre-check
      // (`المقاعد المطلوبة غير متاحة`) both mean the seat is gone.
      if (msg.contains('لم يعد المقعد') || msg.contains('المقاعد المطلوبة')) {
        return const BookingError(
          BookingErrorKind.seatGone,
          'لم يعد المقعد متاحاً، تم حجزه للتو. عد وحدّث قائمة الرحلات.',
        );
      }
      return BookingError(BookingErrorKind.tripClosed, msg);
    case 400:
      return BookingError(BookingErrorKind.invalid, msg);
    case 403:
      // Eligibility gate (a women/family trip only accepts female riders). Use
      // clear, non-judgmental Arabic copy rather than the raw server message.
      return const BookingError(
        BookingErrorKind.notEligible,
        'هذه رحلة نسائية-عائلية ومخصّصة للركّاب من النساء. اختر رحلة عامة للمتابعة.',
      );
    case 404:
      return BookingError(BookingErrorKind.tripClosed, msg);
    default:
      return BookingError(BookingErrorKind.generic, msg);
  }
}
