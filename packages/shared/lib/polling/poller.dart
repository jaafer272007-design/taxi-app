import 'dart:async';

/// A periodic refresh that only runs while somebody is looking.
///
/// ─── WHY POLLING AND NOT A SOCKET ─────────────────────────────────────────
/// Locked decision. Riders and drivers are on unreliable Iraqi mobile
/// networks. A poll recovers from a dropped connection by simply succeeding
/// next time; a socket has to notice it died, back off, reconnect, and
/// re-sync — and a socket that *thinks* it is connected is worse than no
/// socket at all, because the screen looks live while it is frozen. Revisit
/// for Phase 2 live matching. (CLAUDE.md → Refresh & polling.)
/// ──────────────────────────────────────────────────────────────────────────
///
/// Deliberately free of Flutter: no BuildContext, no lifecycle, no widgets.
/// The gating conditions arrive as plain booleans through [setActive], which
/// is what makes the whole start/pause/resume lifecycle testable without
/// pumping a widget tree. [PollingScope] is the thin widget that computes
/// those booleans from the real app.
class Poller {
  Poller({
    required this.interval,
    required this.onPoll,
    this.pollOnResume = true,
  }) : assert(interval > Duration.zero);

  final Duration interval;

  /// The refresh itself. Must not throw — but if it does, [Poller] swallows it
  /// (see [_tick]).
  final Future<void> Function() onPoll;

  /// Fire once immediately when the screen becomes visible again, instead of
  /// waiting out a whole interval. Someone who has just switched back to a
  /// screen is looking at the most stale data they will ever see; making them
  /// wait 30 more seconds for it to correct itself is the wrong trade.
  final bool pollOnResume;

  Timer? _timer;

  /// The caller wants polling (this screen polls at all).
  bool _started = false;

  /// Somebody is actually looking (foreground + visible).
  bool _active = false;

  bool _inFlight = false;
  bool _disposed = false;

  /// True when the timer is genuinely running — the thing the lifecycle tests
  /// assert on, rather than "did we call resume".
  bool get isTicking => _timer != null;

  /// Whether a poll is in flight right now.
  bool get isPolling => _inFlight;

  /// Total completed poll attempts, successful or not. For tests and debugging.
  int pollCount = 0;

  void start() {
    _started = true;
    _sync();
  }

  void stop() {
    _started = false;
    _sync();
  }

  /// Visibility gate: false when the app is backgrounded or the screen is not
  /// on top / not the selected tab.
  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    final resumed = value;
    _sync();
    if (resumed && _started && !_disposed && pollOnResume) {
      unawaited(_tick());
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _sync() {
    final shouldTick = _started && _active && !_disposed;
    if (shouldTick && _timer == null) {
      _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    } else if (!shouldTick && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _tick() async {
    // Never stack requests. On a slow network a 30s interval can easily fire
    // again before the previous response lands, and a queue of overlapping
    // refreshes is how a bad connection turns into a worse one.
    if (_inFlight || _disposed) return;
    _inFlight = true;
    try {
      await onPoll();
    } catch (_) {
      // ─── FAILURES ARE SILENT, ON PURPOSE ────────────────────────────────
      // A failed background poll must not clear the list, show a banner, or
      // interrupt anything. The user did not ask for this refresh and must
      // not be told it failed: they keep the last good data and the next tick
      // tries again. An error here would turn one dropped packet into a
      // screen that looks broken.
      // ────────────────────────────────────────────────────────────────────
    } finally {
      _inFlight = false;
      pollCount++;
    }
  }
}
