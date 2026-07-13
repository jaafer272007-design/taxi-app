/// Iraqi (+964) mobile phone handling — mirrors the backend
/// `normalizeIraqiPhone` (services/api/src/common/phone.util.ts) so client-side
/// validation matches the server.
///
/// Iraqi mobiles are 10 national digits starting with `7`; canonical E.164 is
/// `+9647XXXXXXXXX`.
abstract final class IraqiPhone {
  static final RegExp _national = RegExp(r'^7\d{9}$');
  static final RegExp _strip = RegExp(r'[\s\-().]');

  /// Returns the canonical `+9647XXXXXXXXX` form, or `null` if [input] is not a
  /// valid Iraqi mobile number.
  static String? normalize(String input) {
    var s = input.trim().replaceAll(_strip, '');

    // 00 international prefix → +
    if (s.startsWith('00')) s = '+${s.substring(2)}';

    String national;
    if (s.startsWith('+964')) {
      national = s.substring(4);
    } else if (s.startsWith('964')) {
      national = s.substring(3);
    } else if (s.startsWith('0')) {
      national = s.substring(1); // local form: 077… → 77…
    } else {
      national = s; // assume already national (7…)
    }

    if (!_national.hasMatch(national)) return null;
    return '+964$national';
  }

  static bool isValid(String input) => normalize(input) != null;
}
