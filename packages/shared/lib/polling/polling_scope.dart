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

/// Runs [onPoll] every [interval] while this subtree is genuinely being looked
/// at, and not otherwise.
///
/// "Being looked at" is the conjunction of three things, and all three are
/// needed — each one alone leaves a real hole:
///
///  1. **The app is in the foreground** ([AppLifecycleState.resumed]).
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
    if (widget.enabled) _poller.start();
    _applyGate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // TickerMode changes when the owning shell flips a tab's visibility.
    final visible = TickerMode.of(context);
    if (visible != _tabVisible) {
      _tabVisible = visible;
      _applyGate();
    }

    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
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
    final foreground = state == AppLifecycleState.resumed;
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
