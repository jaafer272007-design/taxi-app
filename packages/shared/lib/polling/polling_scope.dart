import 'package:flutter/material.dart';

import 'poller.dart';

/// The [RouteObserver] that lets [PollingScope] know when its route has been
/// covered by another one.
///
/// Registered by `TaxiApp` on the shared [MaterialApp]. Without it a screen
/// that pushes a detail route on top keeps polling behind it — technically
/// harmless, but it is exactly "polling a screen nobody is looking at", and on
/// a metered Iraqi mobile connection that is somebody's money.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Whether a lifecycle state means "the user can still see this app".
///
/// **[AppLifecycleState.inactive] counts as visible.** This is the whole bug
/// that made polling look dead in live testing, so it is worth stating exactly
/// what the framework means by each state (dart:ui `AppLifecycleState`):
///
/// * `resumed`  — visible, has input focus.
/// * `inactive` — **visible, but WITHOUT input focus.** On the web that is a
///   browser window you have merely clicked away from; on Android it is split
///   screen where the other app is current, a system dialog, the notification
///   shade pulled halfway down, or the app switcher.
/// * `hidden` / `paused` / `detached` — genuinely not on screen. A pocket.
///
/// Gating on `== resumed` therefore gates on FOCUS, not on visibility, and one
/// blur takes down every poller in the app at once — the results list, حجوزاتي,
/// the driver's trip detail and the app-wide notification badge, which is the
/// one that is supposed to survive everything. Opening the driver app to post a
/// trip is enough to do it, which is precisely how this was found.
bool appIsVisible(AppLifecycleState state) => switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        false,
    };

/// Runs [onPoll] every [interval] while this subtree is genuinely being looked
/// at, and not otherwise.
///
/// "Being looked at" is the conjunction of three things, and all three are
/// needed — each one alone leaves a real hole:
///
///  1. **The app is visible** ([appIsVisible]) — not merely focused.
///     Otherwise a phone in a pocket refreshes all night.
///  2. **This route is on top** (via [appRouteObserver]). A rider who opens a
///     trip's details is no longer looking at the results behind it.
///  3. **This tab is selected** (via [TickerMode]). An [IndexedStack] keeps
///     every tab alive and building, so without this the driver's أرباحي tab
///     polls while they are posting a trip. The shells wrap each tab in
///     `TickerMode(enabled: isSelected)` to make this true.
///
/// Conditions 2 and 3 are for a *screen*. An app-wide poll — the notification
/// badge — passes `pauseWhenObscured: false` and keeps only condition 1.
///
/// Failures are swallowed by [Poller] — a failed poll leaves the last good
/// data on screen and says nothing.
class PollingScope extends StatefulWidget {
  const PollingScope({
    super.key,
    required this.interval,
    required this.onPoll,
    required this.child,
    this.enabled = true,
    this.pauseWhenObscured = true,
  });

  final Duration interval;
  final Future<void> Function() onPoll;
  final Widget child;

  /// Turn polling off entirely for this mount — used for screens that are only
  /// live in some states (a settled trip has nothing left to poll for).
  final bool enabled;

  /// Stop when another route covers this one, or when this tab is not the
  /// selected one. True for a screen; **false for an app-wide poll.**
  ///
  /// The notification poll is mounted once above the whole app, and the entire
  /// point of it is that a rider learns their trip was cancelled *whatever they
  /// are looking at*. With this left on, opening a trip's details or the
  /// booking form would silence it — which is exactly the screen someone is on
  /// while the driver cancels underneath them.
  final bool pauseWhenObscured;

  @override
  State<PollingScope> createState() => _PollingScopeState();
}

class _PollingScopeState extends State<PollingScope>
    with WidgetsBindingObserver, RouteAware {
  late final Poller _poller = Poller(
    interval: widget.interval,
    onPoll: () => widget.onPoll(),
  );

  bool _foreground = true;
  bool _routeOnTop = true;
  bool _tabVisible = true;
  ModalRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // SEED, don't assume. addObserver does not replay the current state, and
    // the binding only re-sends on a CHANGE — so a scope mounted while the app
    // is already hidden would otherwise believe it is visible forever.
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || appIsVisible(state);
    if (widget.enabled) _poller.start();
    // No _applyGate() here: TickerMode has not been read yet, so the gate would
    // evaluate as "visible tab" and fire one real request from a tab nobody has
    // selected. didChangeDependencies runs before the first build, so nothing
    // is lost by waiting for it.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // TickerMode changes when the owning shell flips a tab's visibility.
    _tabVisible = TickerMode.of(context);

    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }

    _applyGate();
  }

  @override
  void didUpdateWidget(PollingScope old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled) {
      widget.enabled ? _poller.start() : _poller.stop();
    }
    if (widget.enabled != old.enabled ||
        widget.pauseWhenObscured != old.pauseWhenObscured) {
      _applyGate();
    }
  }

  @override
  void dispose() {
    if (_route != null) appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _poller.dispose();
    super.dispose();
  }

  // ── Gate inputs ───────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Visible, NOT focused — see [appIsVisible]. `inactive` must keep polling.
    final foreground = appIsVisible(state);
    if (foreground == _foreground) return;
    _foreground = foreground;
    _applyGate();
  }

  /// Another route was pushed on top of ours.
  @override
  void didPushNext() {
    _routeOnTop = false;
    _applyGate();
  }

  /// That route popped; we are on top again.
  @override
  void didPopNext() {
    _routeOnTop = true;
    _applyGate();
  }

  void _applyGate() {
    final onScreen =
        widget.pauseWhenObscured ? (_routeOnTop && _tabVisible) : true;
    _poller.setActive(_foreground && onScreen);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
