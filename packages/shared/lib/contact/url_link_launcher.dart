import 'package:url_launcher/url_launcher.dart';

import 'link_launcher.dart';

/// The production [LinkLauncher].
///
/// ─── CONTAINMENT ──────────────────────────────────────────────────────────
/// The ONLY file in the codebase that imports `url_launcher`. Everything else
/// depends on the [LinkLauncher] interface, so the plugin can be swapped and
/// every test can inject a fake that records URIs instead of leaving the app.
/// Same rule as `geolocator` in geolocator_location_service.dart.
/// ──────────────────────────────────────────────────────────────────────────
class UrlLinkLauncher implements LinkLauncher {
  const UrlLinkLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      // externalApplication: a `tel:` or `wa.me` link opened in an in-app
      // webview is a dead end — the whole intent is to leave for the dialer,
      // WhatsApp, or a maps app.
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // launchUrl throws (not returns false) when the platform has no handler
      // at all. To the caller that is the same answer: it did not open, try the
      // next candidate.
      return false;
    }
  }
}
