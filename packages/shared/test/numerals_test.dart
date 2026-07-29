import 'package:flutter_test/flutter_test.dart';
import 'package:shared/format/numerals.dart';

/// The locked numeral rule: DISPLAY values are Arabic-Indic (`٠١٢٣`) with the
/// Arabic thousands separator; INPUT values (phone, OTP) stay Western (`0123`).
void main() {
  group('toArabicDigits', () {
    test('converts Western digits', () {
      expect(toArabicDigits('0123456789'), '٠١٢٣٤٥٦٧٨٩');
    });

    test('leaves punctuation alone — "د.ع" must not gain a decimal separator',
        () {
      // This is the trap: a naive implementation that also maps '.' would turn
      // the dinar suffix into "د٫ع".
      expect(toArabicDigits('د.ع'), 'د.ع');
      expect(toArabicDigits('12,000 د.ع'), '١٢,٠٠٠ د.ع');
    });

    test('leaves non-digit characters untouched', () {
      expect(toArabicDigits('+964 771 234 5678'), '+٩٦٤ ٧٧١ ٢٣٤ ٥٦٧٨');
      expect(toArabicDigits('النجف ← كربلاء'), 'النجف ← كربلاء');
    });
  });

  group('toWesternDigits', () {
    test('converts Arabic-Indic back', () {
      expect(toWesternDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    });

    test('converts Persian (Extended Arabic-Indic) digits too', () {
      expect(toWesternDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });

    test('converts the Arabic separators back to , and .', () {
      expect(toWesternDigits('١٢٬٠٠٠'), '12,000');
      expect(toWesternDigits('٤٫٨'), '4.8');
    });

    test('round-trips with toArabicDigits', () {
      expect(toWesternDigits(toArabicDigits('0123456789')), '0123456789');
    });
  });

  group('formatIqd — display prices', () {
    test('groups thousands with the Arabic separator', () {
      expect(formatIqd(12000), '١٢٬٠٠٠');
      expect(formatIqd(24000), '٢٤٬٠٠٠');
      expect(formatIqd(844000), '٨٤٤٬٠٠٠');
    });

    test('no separator below 1000', () {
      expect(formatIqd(0), '٠');
      expect(formatIqd(999), '٩٩٩');
    });

    test('separator appears exactly at 1000', () {
      expect(formatIqd(1000), '١٬٠٠٠');
    });

    test('handles millions (two separators)', () {
      expect(formatIqd(1234567), '١٬٢٣٤٬٥٦٧');
    });

    test('keeps a leading minus', () {
      expect(formatIqd(-500), '-٥٠٠');
    });

    test('optional dinar suffix', () {
      expect(formatIqd(12000, withSuffix: true), '١٢٬٠٠٠ د.ع');
      expect(formatPrice(24000), '٢٤٬٠٠٠ د.ع');
    });
  });

  group('counts, ratings, clocks, dates', () {
    test('formatCount', () {
      expect(formatCount(4), '٤');
      expect(formatCount(71), '٧١');
    });

    test('formatSeats uses the Arabic dual', () {
      expect(formatSeats(0), 'لا مقاعد');
      expect(formatSeats(1), 'مقعد واحد');
      // The dual — "٢ مقاعد" is wrong Arabic.
      expect(formatSeats(2), 'مقعدان');
      expect(formatSeats(3), '٣ مقاعد');
      expect(formatSeats(4), '٤ مقاعد');
    });

    test('formatRating uses the Arabic decimal separator', () {
      expect(formatRating(4.8), '٤٫٨');
      expect(formatRating(5), '٥٫٠');
    });

    test('formatClock zero-pads', () {
      expect(formatClock(7, 15), '٠٧:١٥');
      expect(formatClock(7, 5), '٠٧:٠٥');
      expect(formatClock(0, 0), '٠٠:٠٠');
      expect(formatClock(14, 0), '١٤:٠٠');
    });

    test('formatTime shifts UTC to Baghdad (+3) by default', () {
      expect(formatTime(DateTime.utc(2026, 7, 28, 4, 30)), '٠٧:٣٠');
      // Crossing midnight backwards.
      expect(formatTime(DateTime.utc(2026, 7, 28, 22, 0)), '٠١:٠٠');
    });

    test('formatTime can skip the Baghdad shift', () {
      expect(
        formatTime(DateTime.utc(2026, 7, 28, 4, 30), toBaghdad: false),
        '٠٤:٣٠',
      );
    });

    test('formatDayShort', () {
      expect(formatDayShort(DateTime(2026, 7, 28)), '٢٨ تموز');
      expect(formatDayShort(DateTime(2026, 1, 3)), '٣ كانون الثاني');
    });
  });

  group('INPUT fields stay Western', () {
    test('a pasted Arabic-Indic phone number normalises for the wire', () {
      // The API only ever sees Western digits.
      expect(toWesternDigits('٠٧٧١٢٣٤٥٦٧٨'), '07712345678');
    });

    test('a Western OTP passes through unchanged', () {
      expect(toWesternDigits('419254'), '419254');
    });

    test(
        'the display formatters are never applied to entry values — '
        'a raw OTP string is not one of their outputs', () {
      // Guard rail: if someone were to route OTP entry through formatCount,
      // the field would show Arabic-Indic and fight the keyboard.
      expect(formatCount(419254), isNot('419254'));
    });
  });
}
