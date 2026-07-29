/// Numeral formatting — the single source of truth for how digits are rendered.
///
/// ## The locked rule
///
/// * **DISPLAY values render in ARABIC-INDIC numerals** (`٠١٢٣`): prices,
///   fares, earnings, times, dates, seat counts, ratings, trip counts.
///   Thousands are grouped with the Arabic thousands separator `٬` (U+066C) and
///   decimals with the Arabic decimal separator `٫` (U+066B) — `١٢٬٠٠٠`, `٤٫٨`.
/// * **INPUT fields stay WESTERN** (`0123`): the phone-number field and the OTP
///   field. An Android keyboard emits Western digits, so echoing Arabic-Indic
///   back into the field the user is typing in causes real friction (caret
///   jumps, mismatched validation, "did it take my number?").
///
/// **Never call [toArabicDigits] on the value of a text input.** For phone and
/// OTP entry the digits stay exactly as the keyboard produced them; only the
/// *labels* around those fields are Arabic.
///
/// Going the other way, [toWesternDigits] normalises anything a user may paste
/// (Arabic-Indic or Persian digits) back to `0-9` before parsing or sending to
/// the API — the wire format is always Western.
library;

/// Arabic-Indic digits, indexed by their Western value. U+0660 … U+0669.
const String arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

/// U+066C ARABIC THOUSANDS SEPARATOR — `١٢٬٠٠٠`.
const String arabicThousandsSeparator = '٬';

/// U+066B ARABIC DECIMAL SEPARATOR — `٤٫٨`.
const String arabicDecimalSeparator = '٫';

/// The Iraqi dinar suffix shown after a price.
const String iqdSuffix = 'د.ع';

const int _western0 = 0x30; // '0'
const int _arabic0 = 0x0660; // '٠'
const int _persian0 = 0x06F0; // '۰' (Extended Arabic-Indic, seen on some IMEs)

/// Converts the Western digits `0-9` in [input] to Arabic-Indic `٠-٩`.
///
/// Only digits are touched — punctuation is left alone, so this is safe to run
/// over a string that already contains Arabic text such as `د.ع` (whose `.` must
/// NOT become a decimal separator).
String toArabicDigits(String input) {
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= _western0 && unit <= _western0 + 9) {
      buffer.writeCharCode(_arabic0 + (unit - _western0));
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Converts Arabic-Indic (`٠-٩`) and Persian (`۰-۹`) digits in [input] back to
/// Western `0-9`, and the Arabic separators back to `,` / `.`.
///
/// Use before parsing or before sending a value to the API — the wire format is
/// always Western.
String toWesternDigits(String input) {
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= _arabic0 && unit <= _arabic0 + 9) {
      buffer.writeCharCode(_western0 + (unit - _arabic0));
    } else if (unit >= _persian0 && unit <= _persian0 + 9) {
      buffer.writeCharCode(_western0 + (unit - _persian0));
    } else if (unit == arabicThousandsSeparator.codeUnitAt(0)) {
      buffer.write(',');
    } else if (unit == arabicDecimalSeparator.codeUnitAt(0)) {
      buffer.write('.');
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Groups [amount] into thousands using the Arabic separator and renders it in
/// Arabic-Indic digits — `12000` → `١٢٬٠٠٠`.
///
/// IQD has no minor unit, so [amount] is always a whole number of dinars.
/// Pass `withSuffix: true` to append ` د.ع`.
String formatIqd(int amount, {bool withSuffix = false}) {
  final digits = amount.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      grouped.write(arabicThousandsSeparator);
    }
    grouped.write(digits[i]);
  }
  final signed = '${amount < 0 ? '-' : ''}${grouped.toString()}';
  final out = toArabicDigits(signed);
  return withSuffix ? '$out $iqdSuffix' : out;
}

/// A price with the dinar suffix — `12000` → `١٢٬٠٠٠ د.ع`.
String formatPrice(int amount) => formatIqd(amount, withSuffix: true);

/// A plain whole number in Arabic-Indic digits — seat counts, trip counts.
String formatCount(int value) => toArabicDigits(value.toString());

/// A rating with one decimal, using the Arabic decimal separator — `4.8` → `٤٫٨`.
String formatRating(double value) {
  final fixed = value.toStringAsFixed(1);
  return toArabicDigits(fixed).replaceAll('.', arabicDecimalSeparator);
}

/// Iraq is UTC+3 year-round (no DST).
const Duration _baghdadOffset = Duration(hours: 3);

/// `HH:mm` in Baghdad wall-clock, in Arabic-Indic digits — `٠٧:١٥`.
///
/// Set [toBaghdad] to false if [dt] is already local wall-clock and must not be
/// shifted again.
String formatTime(DateTime dt, {bool toBaghdad = true}) {
  final t = toBaghdad ? dt.toUtc().add(_baghdadOffset) : dt;
  return formatClock(t.hour, t.minute);
}

/// `HH:mm` from raw hour/minute, in Arabic-Indic digits — `(7, 5)` → `٠٧:٠٥`.
String formatClock(int hour, int minute) {
  final h = hour.toString().padLeft(2, '0');
  final m = minute.toString().padLeft(2, '0');
  return toArabicDigits('$h:$m');
}

/// Arabic (Levantine/Iraqi) month names, indexed 1–12.
const List<String> arabicMonths = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

/// Short Arabic day label with Arabic-Indic digits — `٢٨ تموز`.
String formatDayShort(DateTime date) =>
    '${toArabicDigits(date.day.toString())} ${arabicMonths[date.month - 1]}';
