import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// [Poller] lifecycle: start, pause, resume, stop, dispose — plus the two
/// invariants the whole refresh feature rests on (a failed poll is silent, and
/// polls never stack).
///
/// These run inside `testWidgets` rather than plain `test` so that
/// `Timer.periodic` is driven by flutter_test's fake clock and `tester.pump`
/// advances it deterministically. Nothing here builds a widget; [Poller] is
/// pure Dart and that is exactly why its lifecycle is testable at all.
///
/// Every test disposes its poller inside the body: flutter_test asserts "no
/// pending timers" as part of the test itself, before tearDown runs.
void main() {
  /// An empty frame, so `pump(duration)` has a tree to drive. Nothing here
  /// depends on what is on screen.
  Future<void> boot(WidgetTester t) => t.pumpWidget(const SizedBox.shrink());

  testWidgets('does not tick until BOTH started and active', (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
    );

    // Started but nobody is looking.
    p.start();
    expect(p.isTicking, isFalse);
    await t.pump(const Duration(seconds: 30));
    expect(calls, 0);

    // Visible but never started.
    p.stop();
    p.setActive(true);
    expect(p.isTicking, isFalse);
    await t.pump(const Duration(seconds: 30));
    expect(calls, 0);

    p.dispose();
  });

  testWidgets('polls immediately on becoming visible, then every interval',
      (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
    );

    p.start();
    p.setActive(true);
    await t.pump();

    // The immediate poll: someone who just opened this screen is looking at
    // the most stale data they will ever see.
    expect(calls, 1);
    expect(p.isTicking, isTrue);

    await t.pump(const Duration(seconds: 10));
    expect(calls, 2);
    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);

    p.dispose();
  });

  testWidgets('pollOnResume: false waits out the first interval', (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
      pollOnResume: false,
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(calls, 0);

    await t.pump(const Duration(seconds: 10));
    expect(calls, 1);

    p.dispose();
  });

  testWidgets('pausing stops the timer; resuming polls at once and restarts it',
      (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(calls, 1);

    // Backgrounded / tab switched / covered by another route.
    p.setActive(false);
    expect(p.isTicking, isFalse);
    await t.pump(const Duration(minutes: 5));
    expect(calls, 1, reason: 'a paused screen must not poll at all');

    // Back on screen.
    p.setActive(true);
    await t.pump();
    expect(calls, 2, reason: 'resume refreshes at once, not in 10s');
    expect(p.isTicking, isTrue);

    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);

    p.dispose();
  });

  testWidgets('setActive is idempotent — a repeated true does not re-poll',
      (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(calls, 1);

    p.setActive(true);
    p.setActive(true);
    await t.pump();
    expect(calls, 1);

    p.dispose();
  });

  testWidgets('stop() halts polling even while visible', (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(calls, 1);

    p.stop();
    expect(p.isTicking, isFalse);
    await t.pump(const Duration(minutes: 2));
    expect(calls, 1);

    p.dispose();
  });

  testWidgets('a failing poll is silent and the loop keeps going', (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      // Every other attempt fails, the way a flaky mobile connection does.
      onPoll: () async {
        calls++;
        if (calls.isOdd) throw const ApiException('لا يوجد اتصال بالإنترنت.');
      },
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(calls, 1);

    // The exception must not escape (an uncaught async error fails the test),
    // must not cancel the timer, and must not be reported anywhere.
    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 10));
    expect(calls, 3);
    expect(p.isTicking, isTrue);

    p.dispose();
  });

  testWidgets('polls never stack: a slow request skips the ticks under it',
      (t) async {
    await boot(t);
    var starts = 0;
    final gate = Completer<void>();
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () {
        starts++;
        return gate.future;
      },
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(starts, 1);
    expect(p.isPolling, isTrue);

    // Three intervals pass while the first request is still in the air.
    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 10));
    expect(starts, 1, reason: 'a bad connection must not be given a queue');

    gate.complete();
    await t.pump();
    expect(p.isPolling, isFalse);

    // With the line clear, the next tick goes through.
    await t.pump(const Duration(seconds: 10));
    expect(starts, 2);

    p.dispose();
  });

  testWidgets('dispose cancels the timer and later calls are inert', (t) async {
    await boot(t);
    var calls = 0;
    final p = Poller(
      interval: const Duration(seconds: 10),
      onPoll: () async => calls++,
    );

    p.start();
    p.setActive(true);
    await t.pump();
    expect(calls, 1);

    p.dispose();
    expect(p.isTicking, isFalse);

    // A widget that disposes while a route animation is still settling can
    // still receive gate updates; they must not resurrect the timer.
    p.setActive(false);
    p.setActive(true);
    p.start();
    expect(p.isTicking, isFalse);
    await t.pump(const Duration(minutes: 2));
    expect(calls, 1);
  });
}
