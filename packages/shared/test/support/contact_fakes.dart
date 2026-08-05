import 'package:shared/shared.dart';

/// A [LinkLauncher] that records instead of leaving the app.
///
/// This is the whole reason `url_launcher` sits behind an interface: "tapping
/// اتصال opens the dialer" is not observable in a widget test, but "tapping
/// اتصال launched `tel:+9647701234567`" is — and the URL is the part that
/// actually breaks. A `+` left in a `wa.me` link fails silently on the user's
/// phone and nowhere else.
class FakeLinkLauncher implements LinkLauncher {
  FakeLinkLauncher({this.handles = _everything});

  /// Which URIs this device "has an app for". Defaults to all of them.
  bool Function(Uri) handles;

  final List<Uri> opened = [];

  /// Every URI it was ASKED to open, including ones it refused — the fallback
  /// chain is only testable if the refusals are visible too.
  final List<Uri> attempted = [];

  Uri? get last => opened.isEmpty ? null : opened.last;

  @override
  Future<bool> open(Uri uri) async {
    attempted.add(uri);
    if (!handles(uri)) return false;
    opened.add(uri);
    return true;
  }

  static bool _everything(Uri _) => true;

  /// A device with no `geo:` handler — the case the https maps fallback exists
  /// for. Common in practice: an Android build with no maps app installed.
  factory FakeLinkLauncher.withoutGeo() =>
      FakeLinkLauncher(handles: (u) => u.scheme != 'geo');

  /// A device that can open nothing at all.
  factory FakeLinkLauncher.deaf() => FakeLinkLauncher(handles: (_) => false);
}
