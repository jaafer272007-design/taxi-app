import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// [PollingScope]: the widget that decides when [Poller] is allowed to run.
///
/// The rule under test is "never poll a screen nobody is looking at", and it
/// has three independent inputs. Each is checked on its own here, because each
/// one alone leaves a real hole: the app is backgrounded, another route covers
/// this one, or this tab is not the selected one.
void main() {
  /// A host with the route observer wired the way `TaxiApp` wires it.
  Widget host({
    required Future<void> Function() onPoll,
    bool enabled = true,
    bool tabVisible = true,
    Duration interval = const Duration(seconds: 10),
  }) =>
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: TickerMode(
          enabled: tabVisible,
          child: PollingScope(
            interval: interval,
            onPoll: onPoll,
            enabled: enabled,
            child: const Scaffold(body: Center(child: Text('الرحلات'))),
          ),
        ),
      );

  /// Deliver a lifecycle change to the scope.
  ///
  /// Calls the observer callback the binding itself calls. It exercises the
  /// gate, not the `addObserver` registration one line above it — the reason
  /// for going through the State rather than the binding is that every public
  /// way to fake a platform lifecycle message is either deprecated or
  /// `@protected`, and a test that fails to compile on the next Flutter bump
  /// is worse than one that starts a step late.
  void lifecycle(WidgetTester t, AppLifecycleState state) {
    (t.state(find.byType(PollingScope)) as WidgetsBindingObserver)
        .didChangeAppLifecycleState(state);
  }

  /// Unmount everything, which disposes the scope. Also the assertion that
  /// dispose cancels the timer: flutter_test fails the test on a pending one.
  Future<void> unmount(WidgetTester t) => t.pumpWidget(const SizedBox.shrink());

  testWidgets('polls on mount and then every interval', (t) async {
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++));
    await t.pump();

    expect(calls, 1, reason: 'the screen refreshes as soon as it is looked at');

    await t.pump(const Duration(seconds: 10));
    expect(calls, 2);
    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);

    await unmount(t);
  });

  testWidgets('enabled: false never polls', (t) async {
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++, enabled: false));
    await t.pump(const Duration(minutes: 5));

    expect(calls, 0, reason: 'a settled trip has nothing left to poll for');

    await unmount(t);
  });

  testWidgets('enabling later starts the loop', (t) async {
    var calls = 0;
    Future<void> poll() async => calls++;

    await t.pumpWidget(host(onPoll: poll, enabled: false));
    await t.pump(const Duration(seconds: 30));
    expect(calls, 0);

    // e.g. the rider's first live booking arrives, so حجوزاتي starts polling.
    await t.pumpWidget(host(onPoll: poll, enabled: true));
    await t.pump(const Duration(seconds: 10));
    expect(calls, 1);

    await unmount(t);
  });

  testWidgets('backgrounding pauses; returning refreshes at once', (t) async {
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++));
    await t.pump();
    expect(calls, 1);

    // Phone goes in a pocket.
    lifecycle(t, AppLifecycleState.paused);
    await t.pump(const Duration(minutes: 10));
    expect(calls, 1, reason: 'a backgrounded app must not refresh all night');

    // Phone comes back out.
    lifecycle(t, AppLifecycleState.resumed);
    await t.pump();
    expect(calls, 2, reason: 'the data on screen is minutes old — fix it now');

    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);

    await unmount(t);
  });

  testWidgets('inactive (not just paused) is enough to stop polling',
      (t) async {
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++));
    await t.pump();
    expect(calls, 1);

    lifecycle(t, AppLifecycleState.inactive);
    await t.pump(const Duration(minutes: 2));
    expect(calls, 1);

    await unmount(t);
  });

  testWidgets('an unselected tab does not poll', (t) async {
    var calls = 0;
    Future<void> poll() async => calls++;

    await t.pumpWidget(host(onPoll: poll));
    await t.pump();
    expect(calls, 1);

    // The shells keep every tab mounted in an IndexedStack and flip
    // TickerMode; without this gate أرباحي would poll while the driver is
    // posting a trip.
    await t.pumpWidget(host(onPoll: poll, tabVisible: false));
    await t.pump(const Duration(minutes: 2));
    expect(calls, 1);

    await t.pumpWidget(host(onPoll: poll, tabVisible: true));
    await t.pump();
    expect(calls, 2, reason: 'coming back to a tab refreshes it');

    await unmount(t);
  });

  testWidgets('a route pushed on top pauses; popping it resumes', (t) async {
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++));
    await t.pump();
    expect(calls, 1);

    final navigator = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('التفاصيل'))),
    )));
    await t.pumpAndSettle();
    expect(find.text('التفاصيل'), findsOneWidget);

    final atPush = calls;
    await t.pump(const Duration(minutes: 2));
    expect(calls, atPush,
        reason: 'the results behind a detail page are not being looked at');

    navigator.pop();
    await t.pumpAndSettle();
    await t.pump();
    expect(calls, greaterThan(atPush),
        reason: 'back on top: refresh before the user reads a stale list');

    await unmount(t);
  });
}
