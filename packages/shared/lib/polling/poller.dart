import 'dart:async';

/// The longest a single [Poller.onPoll] may run before the scope is declared
/// stalled and allowed to try again.
///
/// **This number is load-bearing for the locked "polls never stack" rule, and
/// the arithmetic is the whole reason it is safe.**
///
/// `Future.timeout` does NOT cancel the future it wraps — it completes a *new*
/// future and leaves the original running (dart-sdk `future.dart`, `timeout()`:
/// it starts a `Timer`, completes `_future`, and the source's `then` merely
/// finds the timer inactive). So if the watchdog fired while a request were
/// genuinely still on the wire, the next tick would put a second one beside it.
///
/// It cannot, because the request path is itself bounded and this deadline sits
/// far above that bound:
///
/// | leg                                          | bound |
/// |----------------------------------------------|-------|
/// | one request, end to end                      | 45s — `kRequestDeadline`, enforced by CANCELLING it |
/// | the slowest `onPoll` — حجوزاتي, which awaits `listMine` and THEN fans out to the contact endpoints | two sequential request phases = **90s** |
///
/// 150s clears that with margin. Note the leg that is *not* in the table:
/// `connectTimeout + receiveTimeout` is NOT a total bound on Android, where
/// `receiveTimeout` is an inter-chunk idle timer — which is exactly why the
/// real bound is `kRequestDeadline`, and why it cancels rather than abandons.
///
/// This is a recovery mechanism for an await nobody bounded, not a request
/// timeout. If it ever fires in production something is wrong that those bounds
/// did not anticipate, which is why [Poller.stalls] counts it and
/// [Poller.isHealthy] reports it instead of failing silently.
const Duration kPollWatchdog = Duration(seconds: 150);

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
    this.watchdog = kPollWatchdog,
    this.onStall,
  })  : assert(interval > Duration.zero),
        assert(watchdog > Duration.zero);

  final Duration interval;

  /// See [kPollWatchdog]. Overridable so a test can shorten it; production
  /// never sets it.
  final Duration watchdog;

  /// Called when [watchdog] trips. A stall is invisible to the user by design
  /// (a background poll never reports anything), so this exists to make it
  /// visible to a developer — the failure this whole mechanism exists for was
  /// a silent one that reported itself as healthy.
  final void Function(Duration elapsed)? onStall;

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

  /// True when the timer is genuinely running.
  ///
  /// **Not a health check.** It was true throughout the failure this watchdog
  /// exists for: the timer kept firing while every tick returned at the
  /// `_inFlight` guard. Use [isHealthy] to ask whether polls are landing.
  bool get isTicking => _timer != null;

  /// Whether a poll is in flight right now.
  bool get isPolling => _inFlight;

  /// Ticking AND not currently stalled — the honest answer to "is this working".
  bool get isHealthy => isTicking && !_stalled;

  /// True between a watchdog trip and the next poll that completes on time.
  bool get isStalled => _stalled;

  /// Total completed poll attempts, successful or not. For tests and debugging.
  int pollCount = 0;

  /// How many times [watchdog] has tripped. Stays 0 in a healthy app.
  int stalls = 0;

  bool _stalled = false;

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
      // BOUNDED. [_inFlight] is a latch: until this future completes, every
      // later tick returns at the guard above. Without a deadline one hung
      // `onPoll` silences this scope for the life of the screen — and
      // [isTicking] goes on reporting true, so the failure looks healthy.
      //
      // Safe against "polls never stack" because the request path has a REAL
      // ceiling — `kRequestDeadline` cancels, it does not merely give up — and
      // [kPollWatchdog] sits well above it. See that constant for the
      // arithmetic and for why `Future.timeout` not cancelling matters here.
      await onPoll().timeout(watchdog);
      _stalled = false;
    } on TimeoutException {
      // The poll is abandoned, not cancelled — nothing here can reach into it.
      // It is already past every bound the request path has, so letting the
      // next tick run cannot put a second request beside a live one.
      _stalled = true;
      stalls++;
      onStall?.call(watchdog);
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
