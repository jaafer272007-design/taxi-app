import 'dart:async';

import 'package:driver/pool/pool_board_controller.dart';
import 'package:driver/pool/pool_board_screen.dart';
import 'package:driver/pool/pool_models.dart';
import 'package:driver/pool/raise_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/pool_fakes.dart';

/// The driver's half of Phase 2 — the board, and the claim race.
///
/// The thing most worth pinning here is the **race**. Two drivers tap «استلم»
/// at the same instant and exactly one wins; the loser's next move depends
/// entirely on WHY they lost — look for another pool, or wait for this one to
/// refill — and those are opposite instructions. The server classifies it with
/// a code, and this file proves the app keeps the distinction rather than
/// collapsing it into "something went wrong".
void main() {
  group('the board', () {
    test('loads, counts, and reports an explicit failure', () async {
      final api = FakePoolApi()
        ..boardResult = [boardPoolFixture(), boardPoolFixture(id: 'pool_2')];
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();

      expect(c.status, PoolBoardStatus.loaded);
      expect(c.count, 2);

      api.boardError = const ApiException('تعذّر الاتصال بالخادم.');
      await c.load();
      expect(c.status, PoolBoardStatus.error);
      expect(c.error, 'تعذّر الاتصال بالخادم.');
    });

    test('a background refresh that fails keeps the last good board, silently',
        () async {
      final api = FakePoolApi()..boardResult = [boardPoolFixture()];
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();

      api.boardError = const ApiException('لا يوجد اتصال');
      await c.refreshSilently();

      expect(c.pools, hasLength(1), reason: 'the last good board stays');
      expect(c.error, isNull, reason: 'the driver did not ask for this');
      expect(c.status, PoolBoardStatus.loaded);
    });
  });

  group('the claim race', () {
    Future<ClaimResult> claimWith(String? code, String message) async {
      final api = FakePoolApi()
        ..boardResult = [boardPoolFixture()]
        ..claimError = ApiException(message, statusCode: 409, code: code);
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();
      return c.claim('pool_1');
    }

    test('winning returns the trip it became', () async {
      final api = FakePoolApi()
        ..boardResult = [boardPoolFixture()]
        ..claimResult = 'trip_99';
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();

      final result = await c.claim('pool_1');
      expect(result, isA<ClaimWon>());
      expect((result as ClaimWon).tripId, 'trip_99');
    });

    test('THE LOSER is told another driver took it — not a generic error',
        () async {
      final result = await claimWith(
        'POOL_ALREADY_CLAIMED',
        'استلم سائق آخر هذا التجمّع للتوّ.',
      );
      expect(result, isA<ClaimRefused>());
      expect((result as ClaimRefused).refusal, ClaimRefusal.alreadyClaimed);
    });

    test('«انخفض العدد» is a DIFFERENT outcome from «استلمه سائق آخر»',
        () async {
      // The whole reason the server sends a code. One says look elsewhere, the
      // other says wait — and a driver acting on the wrong one wastes a
      // morning.
      final lost = await claimWith(
        'POOL_ALREADY_CLAIMED',
        'استلم سائق آخر هذا التجمّع للتوّ.',
      );
      final shrank = await claimWith(
        'POOL_NOT_VIABLE',
        'انخفض عدد المقاعد؛ لم يعد التجمّع مجدياً.',
      );
      expect((lost as ClaimRefused).refusal, ClaimRefusal.alreadyClaimed);
      expect((shrank as ClaimRefused).refusal, ClaimRefusal.notViable);
      expect(lost.refusal, isNot(shrank.refusal));
    });

    test('an expired pool and a shut window are both "gone", not "taken"',
        () async {
      expect(
        ((await claimWith('POOL_EXPIRED', 'انتهت مهلة هذا التجمّع.'))
                as ClaimRefused)
            .refusal,
        ClaimRefusal.gone,
      );
      expect(
        ((await claimWith('POOL_WINDOW_PASSED', 'انتهت نافذة هذا التجمّع.'))
                as ClaimRefused)
            .refusal,
        ClaimRefusal.gone,
      );
    });

    test('an UNKNOWN code falls back to the server\'s own sentence', () async {
      // An older app meeting a newer server must still say something true.
      final result = await claimWith('SOMETHING_NEW', 'سبب لا يعرفه التطبيق.');
      expect((result as ClaimRefused).refusal, ClaimRefusal.other);
      expect(result.message, 'سبب لا يعرفه التطبيق.');
    });

    test('the board is reloaded after a claim, win or lose', () async {
      // Either the pool is now the driver's trip or it is someone else's;
      // both are things the board must stop showing.
      final api = FakePoolApi()..boardResult = [boardPoolFixture()];
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();
      expect(api.boardCalls, 1);

      await c.claim('pool_1');
      expect(api.boardCalls, 2);
    });

    test('a second tap while one claim is in flight does nothing', () async {
      final api = FakePoolApi()
        ..boardResult = [boardPoolFixture()]
        ..claimGate = Completer<void>();
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();

      final first = c.claim('pool_1');
      expect(c.busy, isTrue);
      await c.claim('pool_1');
      expect(api.claimCalls, hasLength(1));

      api.claimGate!.complete();
      await first;
    });
  });

  group('what the card has to answer', () {
    test('the take now and the take with a full car are different numbers', () {
      // Both, because they answer different questions: what is on offer, and
      // what the driver is driving toward.
      final pool = boardPoolFixture(totalSeats: 3, pricePerSeat: 6000);
      expect(pool.estimatedFare, 18000);
      expect(pool.fullCarFare(4), 24000);
      expect(pool.emptySeats(4), 1);
      expect(pool.emptySeats(3), 0);
    });

    test('stop spread is a straight-line measure, not a route', () {
      // Two points ~500m apart read as tight; across a city as wide.
      final tight = boardPoolFixture(stops: const [
        PoolStop(
          seatCount: 1,
          pickup: LocationPoint(lat: 32.0, lng: 44.30, label: 'أ'),
          dropoff: LocationPoint(lat: 32.6, lng: 44.0, label: 'ب'),
        ),
        PoolStop(
          seatCount: 1,
          pickup: LocationPoint(lat: 32.0, lng: 44.305, label: 'ج'),
          dropoff: LocationPoint(lat: 32.6, lng: 44.0, label: 'د'),
        ),
      ]);
      expect(spreadOf(tight.pickupSpreadMetres, stopCount: 2),
          StopSpread.tight);

      final wide = boardPoolFixture(stops: const [
        PoolStop(
          seatCount: 1,
          pickup: LocationPoint(lat: 32.0, lng: 44.30, label: 'أ'),
          dropoff: LocationPoint(lat: 32.6, lng: 44.0, label: 'ب'),
        ),
        PoolStop(
          seatCount: 1,
          pickup: LocationPoint(lat: 32.08, lng: 44.40, label: 'ج'),
          dropoff: LocationPoint(lat: 32.6, lng: 44.0, label: 'د'),
        ),
      ]);
      expect(spreadOf(wide.pickupSpreadMetres, stopCount: 2), StopSpread.wide);
    });

    test('one stop is not a spread', () {
      expect(spreadOf(0, stopCount: 1), StopSpread.single);
    });
  });

  group('the board screen', () {
    Widget host(PoolBoardController c) => ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
            home: PoolBoardScreen(onClaimed: (_) {}),
          ),
        );

    Future<PoolBoardController> loaded({List<BoardPool>? pools}) async {
      final api = FakePoolApi()..boardResult = pools ?? [boardPoolFixture()];
      final c = PoolBoardController(api: api, vehicleSeats: 4);
      await c.load();
      return c;
    }

    testWidgets('a card answers route, window, seats and both takes',
        (t) async {
      await t.pumpWidget(host(await loaded()));
      await t.pump();

      expect(find.text('النجف'), findsOneWidget);
      expect(find.text('كربلاء'), findsOneWidget);
      // The WINDOW, not a single time.
      expect(find.textContaining('بين'), findsOneWidget);
      expect(find.text('لك الآن'), findsOneWidget);
      expect(find.text('لو امتلأت السيارة'), findsOneWidget);
      expect(find.text(formatPrice(18000)), findsOneWidget);
      expect(find.text(formatPrice(24000)), findsOneWidget);
      expect(find.text('استلم التجمّع'), findsOneWidget);
    });

    testWidgets('no dot-like glyph lands beside an Arabic-Indic digit',
        (t) async {
      // `٠` IS a dot: «٣ مقاعد · ٦٬٠٠٠» has been measured rendering as
      // «٦٬٠٠٠٠». Three seats, never two — `formatSeats(2)` is the Arabic dual
      // and carries no digit to fuse with.
      await t.pumpWidget(host(await loaded()));
      await t.pump();
      expect(_dotOffenders(t), isEmpty);
    });

    testWidgets('the empty board says what would make a pool appear',
        (t) async {
      await t.pumpWidget(host(await loaded(pools: const [])));
      await t.pump();

      expect(find.text('لا توجد تجمّعات جاهزة الآن'), findsOneWidget);
      // Not just "nothing here": a driver who reads an empty screen and no
      // explanation cannot tell a quiet morning from a broken feature.
      expect(find.textContaining('يطلب ركّاب مقاعد'), findsOneWidget);
    });
  });

  // ── The arithmetic the raise decision rests on ────────────────────────

  group('RaiseProjection', () {
    test('states the optimistic AND the minimum case', () {
      const p = RaiseProjection(
        seatsTaken: 3,
        currentPrice: 6000,
        newPrice: 9000,
        minSeats: 2,
      );
      expect(p.takeNow, 18000);
      expect(p.takeIfAllAccept, 27000);
      expect(p.takeIfMinimumAccepts, 18000);
      expect(p.seatsLostAtMinimum, 1);
    });

    test('spots the case where raising is a LOSS, not a gain', () {
      // Four seats at 6000 is 24,000. Push to 7000 and if only the minimum two
      // accept, that is 14,000 — less money AND fewer passengers. The sheet has
      // to be able to say so.
      const p = RaiseProjection(
        seatsTaken: 4,
        currentPrice: 6000,
        newPrice: 7000,
        minSeats: 2,
      );
      expect(p.takeNow, 24000);
      expect(p.takeIfMinimumAccepts, 14000);
      expect(p.minimumIsWorseThanNow, isTrue);
      expect(p.minimumStillBeatsNow, isFalse);
    });

    test('at exactly the minimum, one decline ends the whole trip', () {
      // A different risk from earning less, and it needs a different sentence.
      const p = RaiseProjection(
        seatsTaken: 2,
        currentPrice: 6000,
        newPrice: 9000,
        minSeats: 2,
      );
      expect(p.anyDeclineEndsTrip, isTrue);
      expect(p.seatsLostAtMinimum, 0);

      const safer = RaiseProjection(
        seatsTaken: 3,
        currentPrice: 6000,
        newPrice: 9000,
        minSeats: 2,
      );
      expect(safer.anyDeclineEndsTrip, isFalse);
    });
  });
}

List<String> _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data)
    .whereType<String>()
    .toList();

/// Strings where a dot-like glyph touches an Arabic-Indic digit.
///
/// `٬` (U+066C) and a `:` between two digit runs are exempt — both are part of
/// the number and are supposed to touch the digits.
List<String> _dotOffenders(WidgetTester t) => _allText(t)
    .where((s) =>
        RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·|[^٠-٩\s]\s*:\s*[٠-٩]').hasMatch(s))
    .toList();
