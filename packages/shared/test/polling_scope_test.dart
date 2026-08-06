import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    bool pauseWhenObscured = true,
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
            pauseWhenObscured: pauseWhenObscured,
            child: const Scaffold(body: Center(child: Text('الرحلات'))),
          ),
        ),
      );

  /// Deliver a lifecycle change the way the ENGINE does — a `flutter/lifecycle`
  /// platform message.
  ///
  /// This used to reach into the State and call `didChangeAppLifecycleState`
  /// directly, which tested the gate but not the wiring: nothing proved the
  /// scope was registered with the binding at all, and nothing exercised the
  /// intermediate states `ServicesBinding` synthesises on the way (resumed →
  /// paused really arrives as inactive, hidden, paused). Going through the
  /// messenger is what Flutter's own tests do.
  Future<void> lifecycle(WidgetTester t, AppLifecycleState state) async {
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
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
    await lifecycle(t, AppLifecycleState.paused);
    await t.pump(const Duration(minutes: 10));
    expect(calls, 1, reason: 'a backgrounded app must not refresh all night');

    // Phone comes back out.
    await lifecycle(t, AppLifecycleState.resumed);
    await t.pump();
    expect(calls, 2, reason: 'the data on screen is minutes old — fix it now');

    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);

    await unmount(t);
  });

  testWidgets('inactive means VISIBLE — it must NOT stop polling', (t) async {
    // THE REGRESSION. This test used to assert the opposite, which is why the
    // whole suite stayed green while polling was dead in live use.
    //
    // `inactive` is "visible, but without input focus": a browser window you
    // clicked away from, an Android split screen where the other app is
    // current, a system dialog, the notification shade. Measured in Chromium
    // against the real web build, dispatching a plain window `blur` took the
    // app from 4 requests/40s to ZERO, and it stayed at zero until focus came
    // back — which is exactly what a driver posting a trip in the other app
    // does to the rider's open results screen.
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++));
    await t.pump();
    expect(calls, 1);

    await lifecycle(t, AppLifecycleState.inactive);
    await t.pump(const Duration(seconds: 10));
    expect(calls, 2, reason: 'the user can still see this screen');
    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);

    await unmount(t);
  });

  testWidgets('hidden DOES stop polling — a pocket is still a pocket',
      (t) async {
    var calls = 0;
    await t.pumpWidget(host(onPoll: () async => calls++));
    await t.pump();
    expect(calls, 1);

    // resumed → hidden arrives as inactive, then hidden. The first must not
    // stop it; the second must.
    await lifecycle(t, AppLifecycleState.hidden);
    final atHide = calls;
    await t.pump(const Duration(minutes: 5));
    expect(calls, atHide, reason: 'nothing is on screen to refresh');

    await lifecycle(t, AppLifecycleState.resumed);
    await t.pump();
    expect(calls, greaterThan(atHide), reason: 'back on screen: refresh now');

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

  group('pauseWhenObscured: false — the app-wide notification poll', () {
    // Mounted once above the whole app. A rider learns their trip was
    // cancelled WHATEVER they are looking at, so neither a pushed route nor an
    // unselected tab may silence it — those are precisely the screens somebody
    // is on while the driver cancels underneath them.

    testWidgets('keeps polling behind a pushed route', (t) async {
      var calls = 0;
      await t.pumpWidget(
        host(onPoll: () async => calls++, pauseWhenObscured: false),
      );
      await t.pump();
      expect(calls, 1);

      final navigator = t.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('الحجز'))),
      )));
      await t.pumpAndSettle();
      expect(find.text('الحجز'), findsOneWidget);

      final atPush = calls;
      await t.pump(const Duration(seconds: 10));
      expect(calls, atPush + 1,
          reason: 'the booking form is exactly where a cancellation lands');

      navigator.pop();
      await t.pumpAndSettle();
      await unmount(t);
    });

    testWidgets('keeps polling on an unselected tab', (t) async {
      var calls = 0;
      Future<void> poll() async => calls++;

      await t.pumpWidget(host(onPoll: poll, pauseWhenObscured: false));
      await t.pump();
      expect(calls, 1);

      await t.pumpWidget(
        host(onPoll: poll, pauseWhenObscured: false, tabVisible: false),
      );
      await t.pump(const Duration(seconds: 10));
      expect(calls, 2);

      await unmount(t);
    });

    testWidgets('still stops when the app is backgrounded', (t) async {
      var calls = 0;
      await t.pumpWidget(
        host(onPoll: () async => calls++, pauseWhenObscured: false),
      );
      await t.pump();
      expect(calls, 1);

      await lifecycle(t, AppLifecycleState.paused);
      await t.pump(const Duration(minutes: 10));
      expect(calls, 1, reason: 'a pocket is a pocket, app-wide or not');

      await unmount(t);
    });

    testWidgets('survives losing focus — this is the badge that must not die',
        (t) async {
      // `_foreground` is ANDed OUTSIDE the pauseWhenObscured escape hatch, so
      // before the fix a single blur killed this poll too — the one whose
      // entire purpose is to reach the rider wherever they are. Both reported
      // symptoms had this one shared cause.
      var calls = 0;
      await t.pumpWidget(
        host(onPoll: () async => calls++, pauseWhenObscured: false),
      );
      await t.pump();
      expect(calls, 1);

      await lifecycle(t, AppLifecycleState.inactive);
      await t.pump(const Duration(seconds: 10));
      expect(calls, 2, reason: 'a cancellation must still reach an idle user');

      await unmount(t);
    });
  });
}
