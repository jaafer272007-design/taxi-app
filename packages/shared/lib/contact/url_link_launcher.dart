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
      // ── Do NOT add a canLaunchUrl() guard here ──────────────────────────
      // It looks like a safety improvement and is the opposite. `canLaunchUrl`
      // resolves the intent through the package manager, which on Android 11+
      // (API 30) is subject to package-visibility filtering — so it returns
      // false unless the app's AndroidManifest declares a matching <queries>
      // entry for every scheme. `launchUrl` does not: it calls startActivity
      // directly and reports ActivityNotFoundException, which is what the
      // `false` below means. (Read from url_launcher_android's UrlLauncher.java,
      // not inferred from the README, which documents the rule for
      // canLaunchUrl only.)
      //
      // This repo has no android/ folder committed, so a canLaunchUrl guard
      // would make every action fail on a real device with no way to tell why.
      //
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
