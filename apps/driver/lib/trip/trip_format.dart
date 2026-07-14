// Pure formatting helpers for trip data (no design values here).

/// Iraq is UTC+3 year-round (no DST); show departure in Baghdad wall-clock.
const Duration _baghdadOffset = Duration(hours: 3);

/// `HH:mm` in Baghdad time, from a UTC/any-zone [DateTime].
String formatTime(DateTime dt) {
  final baghdad = dt.toUtc().add(_baghdadOffset);
  final h = baghdad.hour.toString().padLeft(2, '0');
  final m = baghdad.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Thousands-grouped integer, e.g. 12000 → "12,000".
String formatIqd(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Price with the Arabic dinar suffix, e.g. "12,000 د.ع".
String formatPrice(int amount) => '${formatIqd(amount)} د.ع';

const Map<String, String> _cityAr = {
  'Najaf': 'النجف',
  'Karbala': 'كربلاء',
};

/// Arabic name for a stored (English) city; falls back to the input.
String cityAr(String city) => _cityAr[city] ?? city;

const List<String> _arMonths = [
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

/// Short Arabic day label, e.g. "20 تموز".
String formatDayShort(DateTime date) => '${date.day} ${_arMonths[date.month - 1]}';

/// Short Arabic day label in Baghdad wall-clock, from a UTC/any-zone [DateTime].
String formatDayBaghdad(DateTime dt) => formatDayShort(dt.toUtc().add(_baghdadOffset));
