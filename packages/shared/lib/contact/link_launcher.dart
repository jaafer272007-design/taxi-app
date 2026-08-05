/// Hands a URI to whatever app on the device handles it — the dialer, WhatsApp,
/// a maps app.
///
/// Abstracted for the same reason [LocationService] is: the production
/// implementation ([UrlLinkLauncher]) is the ONLY file that imports
/// `url_launcher`, so a widget test can assert *which URL a tap produced*
/// without a platform channel, and swapping the plugin touches one file.
///
/// That assertion is the point. "Tapping call opens the dialer" is not
/// something a test can observe; "tapping call launches `tel:+9647701234567`"
/// is, and it is the part that actually breaks — a `+` in a `wa.me` URL fails
/// silently on the user's phone and nowhere else.
abstract interface class LinkLauncher {
  /// Open [uri]. Returns false when no app on the device handles it — this is
  /// an ordinary outcome, not an error: an Android emulator with no dialer and
  /// a phone with no WhatsApp both land here.
  Future<bool> open(Uri uri);
}

/// Try each URI in order, stopping at the first that opens.
///
/// Navigation needs this: `geo:` is the right intent on Android and opens the
/// user's chosen maps app, but it has no handler on a device without one — so
/// the https maps link follows it. Returns false only if nothing opened at all.
Future<bool> openFirst(LinkLauncher launcher, List<Uri> candidates) async {
  for (final uri in candidates) {
    if (await launcher.open(uri)) return true;
  }
  return false;
}
