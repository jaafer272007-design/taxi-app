import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/booking/my_bookings_controller.dart';
import 'package:rider/booking/my_bookings_screen.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';

/// The two bugs from live end-to-end testing, at the level they were seen:
/// **on screen**, after a trip completed.
///
/// Both slipped past unit tests because neither is a property of a function.
/// One is which list a card is filed under; the other is whether an action
/// exists at all. So these drive the real widget and read what it rendered.
void main() {
  Widget host(MyBookingsController c) => MultiProvider(
        providers: [
          Provider<LinkLauncher>.value(value: _NullLauncher()),
          ChangeNotifierProvider<MyBookingsController>.value(value: c),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MyBookingsScreen(),
          ),
        ),
      );

  /// A phone-sized surface — the default 800×600 is wider than any real screen
  /// and lays the cards out differently.
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<MyBookingsController> loaded(FakeBookingApi api) async {
    final c = MyBookingsController(api: api);
    await c.load();
    return c;
  }

  /// The «سابقة» filter pill — tapping it is how the rider reaches history.
  ///
  /// Anchored rather than exact: the pill renders its count inside the label
  /// («سابقة ٣»), and anchoring keeps it off the empty-state line
  /// «لا توجد رحلات سابقة.», which also contains the word.
  Finder pastPill() => find.textContaining(RegExp('^سابقة'));

  group('BUG 1 — a completed booking is filed under سابقة', () {
    testWidgets('it is NOT under قادمة, and the counts say so', (t) async {
      phone(t);
      // Exactly the reproduction: the ride is done, the badge reads «مكتملة»,
      // and the trip had been scheduled for later. `upcoming: false` is what
      // the fixed server now sends for this row.
      final api = FakeBookingApi()
        ..listMineResult = [
          mineFixture(
            id: 'b1',
            status: BookingStatus.completed,
            upcoming: false,
            ratable: true,
          ),
        ];
      final c = await loaded(api);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();

      // Opens on «قادمة», which must now be empty…
      expect(c.upcoming, isEmpty);
      expect(find.text('لا توجد رحلات قادمة.'), findsOneWidget);

      // …and the ride is waiting under «سابقة».
      await t.tap(pastPill());
      await t.pumpAndSettle();
      expect(find.text('مكتملة'), findsOneWidget);
    });

    testWidgets('a live booking still shows under قادمة', (t) async {
      phone(t);
      final c = await loaded(FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', upcoming: true)]);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();

      expect(find.text('مؤكد'), findsOneWidget);
    });
  });

  group('BUG 2 — the rider can rate the driver', () {
    FakeBookingApi ratableApi({bool rated = false}) => FakeBookingApi()
      ..listMineResult = [
        mineFixture(
          id: 'b1',
          status: BookingStatus.completed,
          upcoming: false,
          ratable: true,
          ratedDriver: rated,
          driverName: 'علي حسن',
        ),
      ];

    testWidgets('the completed ride carries a قيّم السائق action', (t) async {
      phone(t);
      final c = await loaded(ratableApi());
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      await t.tap(pastPill());
      await t.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'قيّم السائق'), findsOneWidget);
    });

    testWidgets('the action opens the rate sheet and submitting posts it',
        (t) async {
      phone(t);
      final api = ratableApi();
      final c = await loaded(api);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      await t.tap(pastPill());
      await t.pumpAndSettle();

      // Invoked directly rather than tapped: the repo's screens exceed the
      // test surface, and every other screen test here does the same.
      t
          .widget<AppButton>(find.widgetWithText(AppButton, 'قيّم السائق'))
          .onPressed!();
      await t.pumpAndSettle();

      expect(find.byType(RateSheet), findsOneWidget);
      expect(find.text('علي حسن'), findsWidgets);

      // Pick four stars, then send.
      t.widget<RatingStars>(find.byType(RatingStars)).onRate!(4);
      await t.pump();
      t
          .widget<AppButton>(find.widgetWithText(AppButton, 'إرسال التقييم'))
          .onPressed!();
      await t.pumpAndSettle();

      expect(api.rateCalls.single.score, 4);
      expect(api.rateCalls.single.toUserId, 'du1');
      expect(find.byType(RateSheet), findsNothing, reason: 'the sheet closes');
    });

    testWidgets('an already-rated ride offers nothing — no rating twice',
        (t) async {
      phone(t);
      final c = await loaded(ratableApi(rated: true));
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      await t.tap(pastPill());
      await t.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'قيّم السائق'), findsNothing);
      expect(find.textContaining('قيّم رحلتك'), findsNothing);
    });

    testWidgets('an unfinished ride cannot be rated', (t) async {
      phone(t);
      final c = await loaded(FakeBookingApi()
        ..listMineResult = [
          mineFixture(id: 'b1', upcoming: true, ratable: false),
        ]);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'قيّم السائق'), findsNothing);
      expect(find.textContaining('قيّم رحلتك'), findsNothing);
    });

    testWidgets('the prompt greets the rider and leads to the sheet', (t) async {
      phone(t);
      final api = ratableApi();
      final c = await loaded(api);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();

      // Visible on «قادمة» — the tab the rider opens on — even though the card
      // it leads to lives under «سابقة». That is the whole point of it.
      expect(find.text('قيّم رحلتك الأخيرة'), findsOneWidget);

      await t.tap(find.text('قيّم رحلتك الأخيرة'));
      await t.pumpAndSettle();
      expect(find.byType(RateSheet), findsOneWidget);
    });

    testWidgets('the prompt disappears once there is nothing left to rate',
        (t) async {
      phone(t);
      final c = await loaded(ratableApi());
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      expect(find.text('قيّم رحلتك الأخيرة'), findsOneWidget);

      await c.rateDriver(bookingId: 'b1', score: 5);
      await t.pumpAndSettle();

      expect(find.text('قيّم رحلتك الأخيرة'), findsNothing);
    });

    testWidgets('never puts a dot beside an Arabic-Indic numeral', (t) async {
      phone(t);
      // Three unrated rides so the prompt renders «لديك ٣ رحلات…» — a count of
      // 1 or 2 uses a word with no digit in it and would render clean either
      // way. See the numerals rule in CLAUDE.md.
      final c = await loaded(FakeBookingApi()
        ..listMineResult = [
          for (final id in ['b1', 'b2', 'b3'])
            mineFixture(
              id: id,
              status: BookingStatus.completed,
              upcoming: false,
              ratable: true,
            ),
        ]);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();

      expect(find.text('لديك ٣ رحلات بانتظار تقييمك'), findsOneWidget);

      final offenders = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
          .toList();
      expect(offenders, isEmpty,
          reason: 'a middle dot touches an Arabic-Indic digit');
    });
  });
}

/// The screen reads a [LinkLauncher] for its contact rows; nothing here taps
/// one, so it only has to exist.
class _NullLauncher implements LinkLauncher {
  @override
  Future<bool> open(Uri uri) async => true;
}
