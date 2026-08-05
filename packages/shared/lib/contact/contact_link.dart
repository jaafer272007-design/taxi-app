import '../map/location_point.dart';

/// The URIs that hand a phone number or a map point off to another app.
///
/// Pure functions on purpose: every rule that is easy to get wrong — the `+`
/// that `wa.me` must NOT have, the one that `tel:` must, the label a maps app
/// shows on the pin — is a string transformation with no plugin, no platform
/// channel and no widget anywhere near it. So they are unit-testable directly,
/// and [LinkLauncher] is left with nothing to decide.
abstract final class ContactLink {
  /// Dial the number: `tel:+9647701234567`.
  ///
  /// Keeps the `+` and the country code. A local-format number (`0770…`) dials
  /// fine from inside Iraq and fails from a roaming SIM, so the E.164 form is
  /// the only one we ever put in front of the dialer.
  static Uri tel(String phone) => Uri(scheme: 'tel', path: _e164(phone));

  /// Open the WhatsApp chat: `https://wa.me/9647701234567`.
  ///
  /// **No `+` and no separators** — wa.me takes bare digits, and anything else
  /// lands on WhatsApp's "phone number shared via url is invalid" page rather
  /// than on the chat. That single character is the whole reason this is a
  /// function and not a string interpolation at each call site.
  static Uri whatsApp(String phone) =>
      Uri.parse('https://wa.me/${_digits(_e164(phone))}');

  /// The Android geo intent for a point: `geo:32.61,44.02?q=32.61,44.02(label)`.
  ///
  /// The `q=` repeat is not redundant: `geo:lat,lng` alone only centres the map,
  /// while `q=` drops an actual pin — and a driver looking at a centred map with
  /// no pin has to guess which building was meant.
  static Uri geo(double lat, double lng, {String label = ''}) {
    final point = '${_coord(lat)},${_coord(lng)}';
    final query = label.trim().isEmpty ? point : '$point(${label.trim()})';
    return Uri.parse('geo:$point?q=${Uri.encodeComponent(query)}');
  }

  /// Cross-platform maps fallback for when no `geo:` handler exists.
  ///
  /// Universal-link form, so it opens the Google Maps app when installed and
  /// the browser when not — either way the driver gets a pin they can navigate
  /// from, which is the point of the action.
  static Uri mapsWeb(double lat, double lng) => Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${_coord(lat)},${_coord(lng)}',
      );

  /// The two navigation URIs to try, best first. See [LinkLauncher.openFirst].
  static List<Uri> navigation(LocationPoint point) => [
        geo(point.lat, point.lng, label: point.label),
        mapsWeb(point.lat, point.lng),
      ];

  /// Display form: `+964 771 234 5678`.
  ///
  /// **Western digits, deliberately** — see the numerals note in
  /// `docs/PHASE1_BUILD_BRIEF.md`. A phone number is an identifier to be dialled
  /// and matched against the device's contact list, not a quantity to be read,
  /// and `+٩٦٤ ٧٧١…` with a leading `+` in an RTL line is a bidi minefield of
  /// exactly the kind that made «٤ مقاعد» render as «٤٠ مقاعد».
  ///
  /// Callers must render it inside `Directionality(TextDirection.ltr)`.
  static String display(String phone) {
    final e164 = _e164(phone);
    final digits = _digits(e164);
    // +964 (3) then the 10-digit national number as 3-3-4.
    if (digits.length != 13 || !digits.startsWith('964')) return e164;
    final n = digits.substring(3);
    return '+964 ${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}';
  }

  /// Normalise to `+964…`, tolerating the local `0770…` and bare `770…` forms
  /// so a number typed by hand into the database still dials.
  static String _e164(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+')) return '+${_digits(trimmed)}';
    final digits = _digits(trimmed);
    if (digits.startsWith('964')) return '+$digits';
    if (digits.startsWith('0')) return '+964${digits.substring(1)}';
    return '+964$digits';
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Coordinates go on the wire in Western digits with a `.` separator — this
  /// is a machine format for another app to parse, never a display value.
  static String _coord(double v) => v.toStringAsFixed(6);
}
