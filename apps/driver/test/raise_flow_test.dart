import 'package:driver/pool/pool_models.dart';
import 'package:driver/pool/raise_controller.dart';
import 'package:driver/pool/raise_panel.dart';
import 'package:driver/pool/raise_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/pool_fakes.dart';

/// Proposing a raise, and the waiting state afterwards.
///
/// The driver is trading certainty for money: every rider may decline and a
/// decliner is **released**, so a higher price per seat can mean less in total.
/// The sheet's job is to make that legible BEFORE the proposal goes out, and
/// these tests assert it rather than trusting the copy to stay honest.
void main() {
  Widget sheetHost(DriverPool pool,
          {Future<String?> Function(int)? onPropose}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: Scaffold(
          body: RaiseSheet(
            pool: pool,
            onPropose: onPropose ?? (_) async => null,
          ),
        ),
      );

  Widget panelHost(RaiseController c) => ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: RaisePanel()),
          ),
        ),
      );

  Future<RaiseController> panelFor(DriverPool? pool) async {
    final api = FakePoolApi()..forTripResult = pool;
    final c = RaiseController(api: api, tripId: 'trip_1');
    await c.load();
    return c;
  }

  // ── The rules, before committing ──────────────────────────────────────

  group('the propose sheet', () {
    testWidgets('states all four rules BEFORE the driver commits', (t) async {
      await t.pumpWidget(sheetHost(driverPoolFixture()));
      await t.pump();

      expect(find.textContaining('اقتراح واحد فقط'), findsOneWidget);
      expect(find.textContaining('لا يتجاوز الحد الأعلى'), findsOneWidget);
      expect(find.textContaining('آخر موعد للاقتراح'), findsOneWidget);
      expect(find.textContaining('يُحتسب رافضاً'), findsOneWidget);
      // …and the cap as an actual number, not just the word.
      expect(find.textContaining(formatPrice(12000)), findsWidgets);
    });

    testWidgets('says plainly that a decliner leaves the trip', (t) async {
      await t.pumpWidget(sheetHost(driverPoolFixture()));
      await t.pump();
      expect(find.textContaining('من يرفض يخرج من الرحلة'), findsOneWidget);
    });

    testWidgets('shows all three outcomes, not only the flattering one',
        (t) async {
      await t.pumpWidget(sheetHost(driverPoolFixture(
        seatsTaken: 3,
        pricePerSeat: 6000,
        minSeats: 2,
      )));
      await t.pump();

      // now, all accept, minimum accepts — 6500 is the opening step.
      expect(find.text(formatPrice(18000)), findsOneWidget); // 3 × 6000
      expect(find.text(formatPrice(19500)), findsOneWidget); // 3 × 6500
      expect(find.text(formatPrice(13000)), findsOneWidget); // 2 × 6500
      expect(find.textContaining('لو وافق الجميع'), findsOneWidget);
      expect(find.textContaining('لو وافق'), findsWidgets);
    });

    testWidgets('opens one step above the current price, never at the cap',
        (t) async {
      // Opening at the maximum would read as a recommendation to charge it.
      await t.pumpWidget(sheetHost(
        driverPoolFixture(pricePerSeat: 6000, maxPricePerSeat: 12000),
      ));
      await t.pump();
      expect(find.text(formatPrice(6500)), findsOneWidget);
      // The cap appears only as a stated bound, never as the chosen value.
      expect(find.textContaining(formatPrice(12000)), findsWidgets);
    });

    testWidgets('cannot be pushed above the corridor cap', (t) async {
      await t.pumpWidget(sheetHost(
        driverPoolFixture(pricePerSeat: 6000, maxPricePerSeat: 7000),
      ));
      await t.pump();

      // Opens at 6500; one step reaches the cap and the control stops.
      await t.tap(find.bySemanticsLabel('زيادة السعر'));
      await t.pump();
      expect(find.text(formatPrice(7000)), findsWidgets);

      await t.tap(find.bySemanticsLabel('زيادة السعر'));
      await t.pump();
      // Still the cap — the app never even offers the request the server
      // would refuse.
      expect(find.text(formatPrice(7500)), findsNothing);
    });

    testWidgets('warns when one refusal would end the whole trip', (t) async {
      // At exactly the minimum, the driver is not risking a smaller fare —
      // they are risking the journey.
      await t.pumpWidget(sheetHost(driverPoolFixture(
        seatsTaken: 2,
        minSeats: 2,
      )));
      await t.pump();
      expect(find.textContaining('تُلغى الرحلة كلها'), findsOneWidget);
    });

    testWidgets('warns when raising could leave the driver WORSE off',
        (t) async {
      await t.pumpWidget(sheetHost(driverPoolFixture(
        seatsTaken: 4,
        seatsTotal: 4,
        pricePerSeat: 6000,
        maxPricePerSeat: 7000,
        minSeats: 2,
      )));
      await t.pump();
      // 4 × 6000 = 24,000 now; 2 × 6500 = 13,000 if only the minimum accepts.
      expect(find.textContaining('بمال أقلّ مما بيدك الآن'), findsOneWidget);
    });

    testWidgets('the server\'s refusal is shown verbatim and the sheet stays',
        (t) async {
      await t.pumpWidget(sheetHost(
        driverPoolFixture(),
        onPropose: (_) async => 'اقترحت رفعاً على هذا التجمّع مسبقاً.',
      ));
      await t.pump();
      await t.tap(find.text('أرسل الاقتراح'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('اقترحت رفعاً على هذا التجمّع مسبقاً.'), findsOneWidget);
      expect(find.text('أرسل الاقتراح'), findsOneWidget);
    });

    testWidgets('sends exactly the price on screen', (t) async {
      final sent = <int>[];
      await t.pumpWidget(sheetHost(
        driverPoolFixture(pricePerSeat: 6000, maxPricePerSeat: 12000),
        onPropose: (p) async {
          sent.add(p);
          return null;
        },
      ));
      await t.pump();
      await t.tap(find.bySemanticsLabel('زيادة السعر'));
      await t.pump();
      await t.tap(find.text('أرسل الاقتراح'));
      await t.pump();

      expect(sent, [7000]);
    });

    testWidgets('no dot-like glyph lands beside an Arabic-Indic digit',
        (t) async {
      await t.pumpWidget(sheetHost(driverPoolFixture(seatsTaken: 3)));
      await t.pump();
      expect(_dotOffenders(t), isEmpty);
    });
  });

  // ── The panel ─────────────────────────────────────────────────────────

  group('the panel on the trip screen', () {
    testWidgets('draws NOTHING for a trip the driver posted', (t) async {
      // Most trips in the app. A panel saying "this has no pool" would be noise
      // on every one of them.
      await t.pumpWidget(panelHost(await panelFor(null)));
      await t.pump();
      expect(find.byType(AppCard), findsNothing);
    });

    testWidgets('offers the raise when the rules allow it', (t) async {
      await t.pumpWidget(panelHost(await panelFor(driverPoolFixture())));
      await t.pump();
      expect(find.text('اقترح سعراً أعلى'), findsOneWidget);
      expect(find.text('رحلة من تجمّع'), findsOneWidget);
    });

    testWidgets('gives the REASON instead of a dead button', (t) async {
      // A driver who cannot act and is not told why assumes the app is broken.
      await t.pumpWidget(panelHost(await panelFor(driverPoolFixture(
        canPropose: false,
        blockedReason: 'امتلأت الرحلة؛ لا مبرّر لرفع السعر.',
      ))));
      await t.pump();

      expect(find.text('اقترح سعراً أعلى'), findsNothing);
      expect(find.text('امتلأت الرحلة؛ لا مبرّر لرفع السعر.'), findsOneWidget);
    });

    testWidgets('the waiting state names every rider and the deadline',
        (t) async {
      await t.pumpWidget(panelHost(await panelFor(
        driverPoolFixture(raise: raiseFixture()),
      )));
      await t.pump();

      expect(find.text('بانتظار ردّ الركّاب'), findsOneWidget);
      expect(find.textContaining('المهلة حتى الساعة'), findsOneWidget);
      expect(find.textContaining('يُحتسب رافضاً'), findsOneWidget);

      // Per rider, by name — a tally alone tells the driver nothing they can
      // act on.
      expect(find.textContaining('أبو حسن'), findsOneWidget);
      expect(find.textContaining('سارة'), findsOneWidget);
      expect(find.text('وافق'), findsOneWidget);
      expect(find.text('لم يردّ بعد'), findsOneWidget);

      // …and as seats, which is what the viability threshold counts.
      expect(find.text('وافقوا'), findsOneWidget);
      expect(find.text('لم يردّوا'), findsOneWidget);
      expect(find.text('رفضوا'), findsOneWidget);
    });

    testWidgets('a resolved raise says what the driver NOW HOLDS', (t) async {
      await t.pumpWidget(panelHost(await panelFor(
        driverPoolFixture(
          raise: raiseFixture(
            resolved: true,
            outcome: RaiseOutcome.accepted,
            responses: const [
              RaiseResponseRow(
                riderName: 'أبو حسن',
                seatCount: 2,
                response: RaiseResponse.accepted,
                released: false,
              ),
              RaiseResponseRow(
                riderName: 'سارة',
                seatCount: 1,
                response: RaiseResponse.declined,
                released: true,
              ),
            ],
          ),
        ),
      )));
      await t.pump();

      expect(find.textContaining('الرحلة بالسعر الجديد'), findsOneWidget);
      expect(find.textContaining('تمضي الرحلة بـ'), findsOneWidget);
      // The released rider stays ON the list, flagged: "where did the third one
      // go?" is a question the driver asks, and deleting the row makes the
      // answer a disappearance.
      expect(find.textContaining('أُطلق'), findsOneWidget);
    });

    testWidgets('a failed raise says the trip is gone and nobody was charged',
        (t) async {
      await t.pumpWidget(panelHost(await panelFor(
        driverPoolFixture(
          raise: raiseFixture(resolved: true, outcome: RaiseOutcome.failed),
        ),
      )));
      await t.pump();

      expect(find.textContaining('أُلغيت الرحلة'), findsWidgets);
      expect(find.textContaining('لم يُحتسب على أحد شيء'), findsOneWidget);
    });

    testWidgets('no dot-like glyph lands beside an Arabic-Indic digit',
        (t) async {
      await t.pumpWidget(panelHost(await panelFor(
        driverPoolFixture(seatsTaken: 3, raise: raiseFixture()),
      )));
      await t.pump();
      expect(_dotOffenders(t), isEmpty);
    });
  });

  // ── The controller ────────────────────────────────────────────────────

  group('RaiseController', () {
    test('isLive only while a raise is unanswered', () async {
      final open = RaiseController(
        api: FakePoolApi()..forTripResult = driverPoolFixture(raise: raiseFixture()),
        tripId: 'trip_1',
      );
      await open.load();
      expect(open.isLive, isTrue);

      final settled = RaiseController(
        api: FakePoolApi()
          ..forTripResult = driverPoolFixture(
            raise: raiseFixture(resolved: true, outcome: RaiseOutcome.accepted),
          ),
        tripId: 'trip_1',
      );
      await settled.load();
      expect(settled.isLive, isFalse);

      final plain = RaiseController(api: FakePoolApi(), tripId: 'trip_1');
      await plain.load();
      expect(plain.isPooled, isFalse);
      expect(plain.isLive, isFalse);
    });

    test('proposing reloads either way, so a refused action stops being offered',
        () async {
      final api = FakePoolApi()..forTripResult = driverPoolFixture();
      final c = RaiseController(api: api, tripId: 'trip_1');
      await c.load();
      expect(api.forTripCalls, 1);

      expect(await c.propose(9000), isNull);
      expect(api.raiseCalls.single, (poolId: 'pool_1', price: 9000));
      expect(api.forTripCalls, 2);

      api.raiseError = const ApiException('فات وقت اقتراح رفع السعر.');
      expect(await c.propose(9500), 'فات وقت اقتراح رفع السعر.');
      expect(api.forTripCalls, 3);
    });

    test('a silent refresh that fails says nothing', () async {
      final api = FakePoolApi()..forTripResult = driverPoolFixture();
      final c = RaiseController(api: api, tripId: 'trip_1');
      await c.load();

      api.forTripError = const ApiException('لا يوجد اتصال');
      await c.refreshSilently();
      expect(c.error, isNull);
      expect(c.pool, isNotNull, reason: 'the last good state stays');
    });
  });
}

List<String> _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data)
    .whereType<String>()
    .toList();

List<String> _dotOffenders(WidgetTester t) => _allText(t)
    .where((s) =>
        RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·|[^٠-٩\s]\s*:\s*[٠-٩]').hasMatch(s))
    .toList();
