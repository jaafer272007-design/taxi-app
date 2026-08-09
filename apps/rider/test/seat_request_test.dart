import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/pool/price_raise_sheet.dart';
import 'package:rider/pool/seat_request_card.dart';
import 'package:rider/pool/seat_request_form_controller.dart';
import 'package:rider/pool/seat_request_models.dart';
import 'package:rider/pool/seat_request_screen.dart';
import 'package:rider/pool/seat_request_sent_screen.dart';
import 'package:rider/pool/seat_requests_controller.dart';
import 'package:shared/shared.dart';

import 'support/pool_fakes.dart';

/// «اطلب مقعد» — the rider's half of Phase 2.
///
/// Three things here are worth pinning, and each of them is a PROMISE rather
/// than a behaviour, which is exactly why they need asserting rather than
/// trusting:
///
///  1. **The price is stated before the rider commits**, and the one way it can
///     move is stated with it.
///  2. **Nothing promises a timeframe.** We do not have one.
///  3. **The price-raise sheet contains no dark pattern**: decline is present,
///     as prominent, not pre-empted, and free — and it says so.
void main() {
  // ── The form ──────────────────────────────────────────────────────────

  group('the request form', () {
    SeatRequestFormController controller({FakeSeatRequestApi? api}) =>
        SeatRequestFormController(
          api: api ?? FakeSeatRequestApi(),
          corridorId: 'c1',
          originCity: 'Najaf',
          destCity: 'Karbala',
          pricePerSeat: 6000,
          day: DateTime(2026, 8, 12),
        );

    test('a window, not a time — and it must run forwards', () {
      final c = controller();
      // The default is a real span: pooling matches on OVERLAP, so a form that
      // opened with from == to would ask for the one shape that pools nobody.
      expect(c.windowEnd.isAfter(c.windowStart), isTrue);

      c.setWindow(const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 8, minute: 0));
      expect(c.canSubmit, isFalse);
      expect(c.blockedReason, contains('حتى'));
    });

    test('both points are required, and the reason says which', () {
      final c = controller();
      expect(c.canSubmit, isFalse);
      expect(c.blockedReason, contains('الانطلاق'));

      c.setPickupPoint(const GeoPoint(lat: 32, lng: 44, label: 'ن'));
      expect(c.canSubmit, isFalse);
      expect(c.blockedReason, contains('النزول'));

      c.setDropoffPoint(const GeoPoint(lat: 32.6, lng: 44, label: 'و'));
      expect(c.canSubmit, isTrue);
      expect(c.blockedReason, isNull);
    });

    test('the total follows the seat count, and the cap is the booking cap', () {
      final c = controller();
      expect(c.totalFare, 6000);
      c.setSeatCount(3);
      expect(c.totalFare, 18000);
      // Same @Max(4) the booking DTO enforces — the form cannot offer a number
      // the server would refuse.
      c.setSeatCount(9);
      expect(c.seatCount, 4);
    });

    test('the window goes out as UTC; the form works in the local clock', () async {
      final api = FakeSeatRequestApi();
      final c = controller(api: api)
        ..setPickupPoint(const GeoPoint(lat: 32, lng: 44, label: 'ن'))
        ..setDropoffPoint(const GeoPoint(lat: 32.6, lng: 44, label: 'و'))
        ..setWindow(const TimeOfDay(hour: 7, minute: 0),
            const TimeOfDay(hour: 10, minute: 0));

      expect(await c.submit(), isTrue);
      final json = api.lastDraft!.toJson();
      expect(json['windowStart'], endsWith('Z'));
      expect(json['windowEnd'], endsWith('Z'));
      expect(
        DateTime.parse(json['windowEnd'] as String)
            .isAfter(DateTime.parse(json['windowStart'] as String)),
        isTrue,
      );
      expect(json['seatCount'], 1);
    });

    test("the server's own words survive a refusal", () async {
      // A blocked rider, an overlapping request, a window it will not take:
      // every one of those says something the rider can act on, so none of them
      // may be flattened into "something went wrong".
      final api = FakeSeatRequestApi()
        ..createError = const ApiException(
            'لديك طلب على هذا المسار في نفس الوقت.',
            statusCode: 409);
      final c = controller(api: api)
        ..setPickupPoint(const GeoPoint(lat: 32, lng: 44, label: 'ن'))
        ..setDropoffPoint(const GeoPoint(lat: 32.6, lng: 44, label: 'و'));

      expect(await c.submit(), isFalse);
      expect(c.error, contains('لديك طلب على هذا المسار'));
      expect(c.submitting, isFalse);
    });
  });

  // ── What the form shows before the rider commits ──────────────────────

  group('the form screen', () {
    Widget host(SeatRequestFormController c) => MultiProvider(
          providers: [
            ChangeNotifierProvider<SeatRequestFormController>.value(value: c),
            Provider<LocationService>.value(value: const _NullLocation()),
            Provider<ReverseGeocoder>.value(value: const NullReverseGeocoder()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: SeatRequestScreen(),
            ),
          ),
        );

    SeatRequestFormController filled() => SeatRequestFormController(
          api: FakeSeatRequestApi(),
          corridorId: 'c1',
          originCity: 'Najaf',
          destCity: 'Karbala',
          pricePerSeat: 6000,
          day: DateTime(2026, 8, 12),
        )
          ..setSeatCount(3)
          ..setPickupPoint(
              const GeoPoint(lat: 32, lng: 44, label: 'كراج النجف'))
          ..setDropoffPoint(
              const GeoPoint(lat: 32.6, lng: 44, label: 'مرآب كربلاء'));

    testWidgets('the price and the total are on screen BEFORE the CTA',
        (t) async {
      await _pumpTall(t, host(filled()));

      expect(find.text('سعر المقعد'), findsOneWidget);
      expect(find.text(formatPrice(6000)), findsOneWidget);
      expect(find.text(formatPrice(18000)), findsOneWidget);

      // …and the CTA sits BELOW them in the scroll order, so the price cannot
      // be a thing the rider discovers after tapping.
      final priceY = t.getTopLeft(find.text(formatPrice(18000))).dy;
      final ctaY = t.getTopLeft(find.text('أرسل الطلب')).dy;
      expect(priceY, lessThan(ctaY));
    });

    testWidgets('the one way the price can move is stated, not buried',
        (t) async {
      await _pumpTall(t, host(filled()));
      expect(find.textContaining('هذا ما ستدفعه'), findsOneWidget);
      expect(find.textContaining('قد يقترح السائق سعراً أعلى'), findsOneWidget);
      // And that refusing costs nothing, said here too — the rider decides
      // whether to send the request knowing both halves.
      expect(find.textContaining('الرفض بلا أي رسوم'), findsOneWidget);
    });

    testWidgets('a request is not a booking, and no timeframe is promised',
        (t) async {
      await _pumpTall(t, host(filled()));
      expect(find.textContaining('هذا طلب وليس حجزاً'), findsOneWidget);
      _expectNoTimeframePromise(t);
    });

    testWidgets('no dot-like glyph lands beside an Arabic-Indic digit',
        (t) async {
      // `٠` IS a dot: «الإجمالي · ٣ مقاعد» renders as «٣٠ مقاعد», and a fused
      // fare reads as ten times the price. Three seats, not two — `formatSeats`
      // returns the dual «مقعدان» at 2, which carries no digit to fuse with.
      await _pumpTall(t, host(filled()));
      expect(_dotOffenders(t), isEmpty);
    });
  });

  // ── The confirmation ──────────────────────────────────────────────────

  group('«أرسلنا طلبك»', () {
    Widget host() => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: SeatRequestSentScreen(
              originCity: 'Najaf',
              destCity: 'Karbala',
              windowStart: DateTime(2026, 8, 12, 7, 30),
              windowEnd: DateTime(2026, 8, 12, 10, 30),
              seatCount: 3,
              pricePerSeat: 6000,
            ),
          ),
        );

    testWidgets('confirms what was recorded and promises no date', (t) async {
      await t.pumpWidget(host());
      await t.pump();

      expect(find.text('أرسلنا طلبك'), findsOneWidget);
      // Told either way — the honest half riders actually need.
      expect(find.textContaining('وأيضاً إن لم تتوفّر'), findsOneWidget);
      _expectNoTimeframePromise(t);
    });

    testWidgets('joins the two clock times with a word, never an arrow',
        (t) async {
      await t.pumpWidget(host());
      await t.pump();
      // Cairo has no arrow glyph — an «→» here ships a tofu box.
      expect(_allText(t).where((s) => s.contains('→') || s.contains('←')),
          isEmpty);
      expect(find.textContaining('إلى'), findsWidgets);
      expect(_dotOffenders(t), isEmpty);
    });
  });

  // ── The stage model ───────────────────────────────────────────────────

  group('stages', () {
    test('an unknown stage renders as neutral, never as wrong', () {
      // An old app meeting a newer server must not claim a state it cannot
      // know. `unknown` is neither live nor terminal and offers no action.
      expect(seatRequestStageFrom('SOMETHING_NEW'), SeatRequestStage.unknown);
      expect(SeatRequestStage.unknown.isLive, isFalse);
      expect(SeatRequestStage.unknown.canCancel, isFalse);
    });

    test('only an unclaimed request can be cancelled AS A REQUEST', () {
      // Once claimed it is a booking, and cancelling goes through the booking
      // rules — the server refuses anything else, so offering it would be an
      // action that answers with an error.
      expect(SeatRequestStage.waitingForRiders.canCancel, isTrue);
      expect(SeatRequestStage.waitingForDriver.canCancel, isTrue);
      expect(SeatRequestStage.raisePending.canCancel, isFalse);
      expect(SeatRequestStage.claimed.canCancel, isFalse);
    });

    test('a claimed request is no longer live — the booking is the story', () {
      expect(SeatRequestStage.claimed.isLive, isFalse);
      expect(SeatRequestStage.waitingForDriver.isLive, isTrue);
      expect(SeatRequestStage.raisePending.isLive, isTrue);
    });
  });

  // ── The controller ────────────────────────────────────────────────────

  group('SeatRequestsController', () {
    test('a background refresh that fails keeps the last good list, silently',
        () async {
      final api = FakeSeatRequestApi()
        ..listMineResult = [seatRequestFixture()];
      final c = SeatRequestsController(api: api);
      await c.load();
      expect(c.live, hasLength(1));

      api.listMineError = const ApiException('لا يوجد اتصال');
      await c.refreshSilently();

      expect(c.live, hasLength(1), reason: 'the last good data stays');
      expect(c.error, isNull, reason: 'the rider did not ask for this refresh');
      expect(c.status, SeatRequestsStatus.loaded);
    });

    test('an explicit load DOES report its failure', () async {
      final api = FakeSeatRequestApi()
        ..listMineError = const ApiException('تعذّر الاتصال بالخادم.');
      final c = SeatRequestsController(api: api);
      await c.load();
      expect(c.status, SeatRequestsStatus.error);
      expect(c.error, 'تعذّر الاتصال بالخادم.');
    });

    test('hasLiveRequests drives the poll, and a settled list stops it',
        () async {
      final api = FakeSeatRequestApi()
        ..listMineResult = [
          seatRequestFixture(stage: SeatRequestStage.waitingForDriver),
        ];
      final c = SeatRequestsController(api: api);
      await c.load();
      expect(c.hasLiveRequests, isTrue);

      api.listMineResult = [
        seatRequestFixture(stage: SeatRequestStage.claimed, bookingId: 'b1'),
      ];
      await c.refreshSilently();
      // Nothing left to learn here: the booking list owns it now.
      expect(c.hasLiveRequests, isFalse);
    });

    test('pendingRaise surfaces only an UNANSWERED raise', () async {
      final api = FakeSeatRequestApi()
        ..listMineResult = [
          seatRequestFixture(
            stage: SeatRequestStage.raisePending,
            raise: raiseFixture(),
          ),
        ];
      final c = SeatRequestsController(api: api);
      await c.load();
      expect(c.pendingRaise, isNotNull);

      api.listMineResult = [
        seatRequestFixture(stage: SeatRequestStage.claimed, bookingId: 'b1'),
      ];
      await c.refreshSilently();
      expect(c.pendingRaise, isNull);
    });

    test('declining is a first-class action that reaches the server', () async {
      final api = FakeSeatRequestApi()
        ..listMineResult = [
          seatRequestFixture(
            stage: SeatRequestStage.raisePending,
            raise: raiseFixture(),
          ),
        ];
      final c = SeatRequestsController(api: api);
      await c.load();

      expect(await c.respondToRaise('sr_1', accept: false), isNull);
      expect(api.raiseResponses.single, (id: 'sr_1', accept: false));
      // Reloaded either way: a screen still offering a choice already made is
      // worse than a slow one.
      expect(api.listMineCalls, 2);
    });

    test('a failed answer returns the message and leaves the choice open',
        () async {
      final api = FakeSeatRequestApi()
        ..listMineResult = [
          seatRequestFixture(
            stage: SeatRequestStage.raisePending,
            raise: raiseFixture(),
          ),
        ]
        ..respondError = const ApiException('انتهت مهلة الردّ.');
      final c = SeatRequestsController(api: api);
      await c.load();

      expect(await c.respondToRaise('sr_1', accept: true),
          'انتهت مهلة الردّ.');
      expect(c.pendingRaise, isNotNull);
    });
  });

  // ── The price raise: the delicate one ─────────────────────────────────

  group('the price-raise sheet', () {
    Widget host(SeatRequest request,
            {Future<String?> Function({required bool accept})? onRespond}) =>
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PriceRaiseSheet(
                request: request,
                onRespond: onRespond ?? ({required bool accept}) async => null,
              ),
            ),
          ),
        );

    SeatRequest raised({int seats = 3}) => seatRequestFixture(
          stage: SeatRequestStage.raisePending,
          seatCount: seats,
          pricePerSeat: 6000,
          raise: raiseFixture(oldPricePerSeat: 6000, newPricePerSeat: 9000),
        );

    testWidgets('old and new side by side, with the difference spelled out',
        (t) async {
      await t.pumpWidget(host(raised()));
      await t.pump();

      expect(find.text('السعر الحالي'), findsOneWidget);
      expect(find.text('السعر المقترح'), findsOneWidget);
      expect(find.text(formatPrice(6000)), findsOneWidget);
      expect(find.text(formatPrice(9000)), findsOneWidget);
      // The arithmetic the rider should not have to do under time pressure.
      expect(find.text('الفرق للمقعد'), findsOneWidget);
      expect(find.text(formatPrice(3000)), findsOneWidget);
      expect(find.text(formatPrice(27000)), findsOneWidget,
          reason: 'the new total for 3 seats');

      // Side by side, literally: same row, so neither is above the fold.
      final oldY = t.getTopLeft(find.text('السعر الحالي')).dy;
      final newY = t.getTopLeft(find.text('السعر المقترح')).dy;
      expect(oldY, closeTo(newY, 1));
    });

    testWidgets('declining is present, as large as accepting, and NOT hidden',
        (t) async {
      await t.pumpWidget(host(raised()));
      await t.pump();

      final accept = find.text('أوافق على السعر الجديد');
      final decline = find.text('أرفض وألغِ حجزي');
      expect(accept, findsOneWidget);
      expect(decline, findsOneWidget);

      // Same width and the same height, directly under it — never a text link,
      // never below the fold.
      final acceptBox = t.getRect(
          find.ancestor(of: accept, matching: find.byType(AppButton)).first);
      final declineBox = t.getRect(
          find.ancestor(of: decline, matching: find.byType(AppButton)).first);
      expect(declineBox.width, closeTo(acceptBox.width, 1));
      expect(declineBox.height, closeTo(acceptBox.height, 1));
      expect(declineBox.top, greaterThan(acceptBox.top));
      // On screen, not scrolled past the bottom edge.
      expect(declineBox.bottom, lessThanOrEqualTo(t.view.physicalSize.height));
    });

    testWidgets('the current price is not struck through — nothing presumes '
        'the answer', (t) async {
      // A line through it says "this no longer applies", but until the rider
      // answers it is still the price they are owed — and it is the number
      // they have to READ to judge the offer. The first golden showed it as
      // the harder of the two to read, which is the wrong way round.
      await t.pumpWidget(host(raised()));
      await t.pump();

      final current = t.widget<Text>(find.text(formatPrice(6000)));
      expect(current.style?.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('neither answer is pre-selected — nothing happens on its own',
        (t) async {
      var calls = 0;
      await t.pumpWidget(host(raised(),
          onRespond: ({required bool accept}) async {
        calls++;
        return null;
      }));
      // Pump well past every animation. A pre-selected default would fire here.
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
    });

    testWidgets('the deadline is a plain time and silence is written down',
        (t) async {
      await t.pumpWidget(host(raised()));
      await t.pump();

      final deadline = _allText(t).firstWhere((s) => s.contains('مهلة الردّ'));
      // A fact, not a drumbeat: a clock time, not «متبقٍ ٠٩:٥٩».
      expect(deadline, contains(formatTime(raiseFixture().respondBy)));
      expect(deadline, contains('يُعتبر ذلك رفضاً'));
      expect(deadline, isNot(contains('متبق')));
      expect(_allText(t).where((s) => s.contains('أسرع') || s.contains('عجّل')),
          isEmpty,
          reason: 'no urgency copy');
    });

    testWidgets('«الرفض مجاني» is said in words — no fee, no no-show',
        (t) async {
      await t.pumpWidget(host(raised()));
      await t.pump();
      final free = _allText(t).firstWhere((s) => s.contains('الرفض مجاني'));
      expect(free, contains('لا رسوم'));
      expect(free, contains('غياباً'));
    });

    testWidgets('accepting and declining each reach the server exactly once',
        (t) async {
      final answers = <bool>[];
      await t.pumpWidget(host(raised(),
          onRespond: ({required bool accept}) async {
        answers.add(accept);
        return null;
      }));
      await t.pump();
      await t.tap(find.text('أرفض وألغِ حجزي'));
      await t.pump();
      expect(answers, [false]);
    });

    testWidgets('a failure keeps the sheet open with the choice intact',
        (t) async {
      await t.pumpWidget(host(raised(),
          onRespond: ({required bool accept}) async => 'انتهت مهلة الردّ.'));
      await t.pump();
      await t.tap(find.text('أوافق على السعر الجديد'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('انتهت مهلة الردّ.'), findsOneWidget);
      expect(find.text('أرفض وألغِ حجزي'), findsOneWidget);
    });

    testWidgets('no dot-like glyph lands beside an Arabic-Indic digit',
        (t) async {
      await t.pumpWidget(host(raised()));
      await t.pump();
      expect(_dotOffenders(t), isEmpty);
    });
  });

  // ── The request card ──────────────────────────────────────────────────

  group('the request card', () {
    Widget host(SeatRequest r, {VoidCallback? onCancel}) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SeatRequestCard(request: r, onCancel: onCancel),
            ),
          ),
        );

    testWidgets('says what it is waiting for, and promises no timeframe',
        (t) async {
      await t.pumpWidget(host(
          seatRequestFixture(stage: SeatRequestStage.waitingForRiders)));
      await t.pump();

      expect(find.text('بانتظار ركّاب آخرين'), findsOneWidget);
      expect(find.textContaining('نجمعك مع ركّاب آخرين'), findsOneWidget);
      _expectNoTimeframePromise(t);
      expect(_dotOffenders(t), isEmpty);
    });

    testWidgets('«بانتظار سائق» is a different sentence, not the same one',
        (t) async {
      // Both are «still waiting», but they are different facts about the pool
      // and a rider deciding whether to keep waiting needs to tell them apart.
      await t.pumpWidget(host(
          seatRequestFixture(stage: SeatRequestStage.waitingForDriver)));
      await t.pump();
      expect(find.text('بانتظار سائق'), findsOneWidget);
      expect(find.textContaining('اكتمل العدد'), findsOneWidget);
    });

    testWidgets('an expired request says nobody was charged', (t) async {
      await t.pumpWidget(
          host(seatRequestFixture(stage: SeatRequestStage.expired)));
      await t.pump();
      expect(find.textContaining('لم تُحاسب على شيء'), findsOneWidget);
    });
  });
}

/// Pump on a 390-wide but very TALL surface.
///
/// These screens scroll on a phone, and a widget scrolled out of view is not in
/// the element tree — so at 390×844 half the assertions below would be about
/// what happened to fit rather than about what the screen says. Height is the
/// goldens' job; this is about content and order.
Future<void> _pumpTall(WidgetTester t, Widget app) async {
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(app);
  await t.pump();
}

/// Every rendered string on screen.
List<String> _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data)
    .whereType<String>()
    .toList();

/// Strings where a dot-like glyph touches an Arabic-Indic digit.
///
/// `٠` IS a dot, and `·` is bidi-neutral so it can be reordered onto the far
/// side of a number: «٣ مقاعد · ٦٬٠٠٠» has been measured rendering as «٦٬٠٠٠٠».
/// A `:` immediately BEFORE a digit is the same hazard (the WhatsApp rule),
/// which is why every field here joins with a strong Arabic word instead.
///
/// Two things are deliberately exempt: `٬` (U+066C) and `٫` (U+066B), which are
/// *part* of the number and are supposed to touch the digits; and a `:` between
/// two digit runs — `٠٧:٣٠` sits inside one directional run and renders
/// correctly.
List<String> _dotOffenders(WidgetTester t) => _allText(t)
    .where((s) =>
        RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·|[^٠-٩\s]\s*:\s*[٠-٩]').hasMatch(s))
    .toList();

/// Nothing on screen may promise when this will happen. We do not know.
void _expectNoTimeframePromise(WidgetTester t) {
  final offenders = _allText(t)
      .where((s) => RegExp('قريباً|خلال ساعة|خلال يوم|خلال دقائق').hasMatch(s))
      .toList();
  expect(offenders, isEmpty,
      reason: 'a timeframe was promised that we cannot keep');
}

/// Device location that always declines — the map opens on the city centre,
/// which is what the form seeds it with anyway.
class _NullLocation implements LocationService {
  const _NullLocation();

  @override
  Future<LocationResult> currentLocation() async =>
      const LocationResult(LocationStatus.denied);
}
