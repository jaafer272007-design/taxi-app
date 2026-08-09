import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/trip/results_screen.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:rider/trip/trip_search_controller.dart';
import 'package:shared/shared.dart';

import 'support/trip_fakes.dart';

/// «أبلغنا أنك تريد هذا المسار» — the empty state's optional action.
///
/// The point of the feature is a COUNT the panel ranks corridors by, so the two
/// things worth pinning here are (a) that a rider can register interest in one
/// tap, and (b) that nothing on this screen can inflate that count or promise
/// something we cannot keep.

/// A controller sitting on an empty result, plus the fake behind it.
typedef Harness = ({TripSearchController c, FakeTripApi api});

Future<Harness> emptyController({
  Gender? driverGender,
  DateTime? date,
  Object? error,
  List<Corridor> corridors = const [najafKarbala],
}) async {
  final api = FakeTripApi()
    ..corridors = corridors
    ..searchResults = const []
    ..requestRouteError = error;
  final c = TripSearchController(api: api);
  await c.ensureCorridorsLoaded();
  if (driverGender != null) c.setDriverGender(driverGender);
  if (date != null) c.setDate(date);
  await c.search();
  return (c: c, api: api);
}

void main() {
  group('when the action is offered at all', () {
    test('offered on an unfiltered empty result', () async {
      final (:c, :api) = await emptyController();
      expect(c.status, TripSearchStatus.empty);
      expect(c.canRequestRoute, isTrue);
    });

    test('NOT offered while a filter is active — one screen, one primary action',
        () async {
      // A filtered-empty result has a cheaper remedy («إزالة الفلاتر») and would
      // record demand for a corridor whose real supply was never asked about.
      final (:c, :api) = await emptyController(driverGender: Gender.female);
      expect(c.status, TripSearchStatus.empty);
      expect(c.canRequestRoute, isFalse);
    });

    test('offered again once the filters are cleared', () async {
      final (:c, :api) = await emptyController(driverGender: Gender.female);
      expect(c.canRequestRoute, isFalse);
      c.clearFilters();
      await c.search();
      expect(c.canRequestRoute, isTrue);
    });

    test('NOT offered when the city pair has no corridor at all', () async {
      // Nothing to attach demand to. The 306-pair grid makes this rare, but a
      // corridor id is what the whole aggregate is keyed on.
      final (:c, :api) = await emptyController(corridors: const []);
      expect(c.matchedCorridor, isNull);
      expect(c.canRequestRoute, isFalse);
    });

    test('NOT offered when there ARE results', () async {
      final api = FakeTripApi()
        ..corridors = const [najafKarbala]
        ..searchResults = [tripFixture()];
      final c = TripSearchController(api: api);
      await c.ensureCorridorsLoaded();
      await c.search();
      expect(c.status, TripSearchStatus.results);
      expect(c.canRequestRoute, isFalse);
    });
  });

  group('sending', () {
    test('sends the matched corridor and reaches sent', () async {
      final (:c, :api) = await emptyController();
      expect(c.routeRequestStatus, RouteRequestStatus.idle);

      await c.requestRoute();

      expect(api.requestRouteCalls, 1);
      expect(api.lastRequestedCorridorId, 'c1');
      expect(c.routeRequestStatus, RouteRequestStatus.sent);
      expect(c.routeRequestError, isNull);
    });

    test('carries the date the rider was searching, as context', () async {
      final when = DateTime(2026, 8, 20);
      final (:c, :api) = await emptyController(date: when);
      await c.requestRoute();
      expect(api.lastRequestedFor, when);
    });

    test('a second tap does NOT send again — the count must not inflate',
        () async {
      final (:c, :api) = await emptyController();
      await c.requestRoute();
      await c.requestRoute();
      await c.requestRoute();
      expect(api.requestRouteCalls, 1);
      expect(c.routeRequestStatus, RouteRequestStatus.sent);
    });

    test('reports failure — the rider asked, so silence would look like success',
        () async {
      final (:c, :api) = await emptyController(
        error: const ApiException('تعذّر الاتصال بالخادم.'),
      );
      await c.requestRoute();
      expect(c.routeRequestStatus, RouteRequestStatus.failed);
      expect(c.routeRequestError, 'تعذّر الاتصال بالخادم.');
    });

    test('a failure can be retried', () async {
      final (:c, :api) = await emptyController(
        error: const ApiException('تعذّر الاتصال بالخادم.'),
      );
      await c.requestRoute();
      expect(c.routeRequestStatus, RouteRequestStatus.failed);

      api.requestRouteError = null;
      await c.requestRoute();
      expect(c.routeRequestStatus, RouteRequestStatus.sent);
      expect(api.requestRouteCalls, 2);
    });

    test('an unexpected (non-Api) error still produces an Arabic message',
        () async {
      final (:c, :api) = await emptyController(error: StateError('boom'));
      await c.requestRoute();
      expect(c.routeRequestStatus, RouteRequestStatus.failed);
      expect(c.routeRequestError, 'تعذّر إرسال طلبك. حاول مرة أخرى.');
    });
  });

  group('the confirmation belongs to ONE route', () {
    test('changing the destination resets it', () async {
      final (:c, :api) = await emptyController(
        corridors: const [najafKarbala, karbalaNajaf],
      );
      await c.requestRoute();
      expect(c.routeRequestStatus, RouteRequestStatus.sent);

      c.swapCities();

      // Otherwise «سنخبرك عندما تتوفر رحلات على هذا المسار» would sit under a
      // route we never recorded — a promise we are not keeping.
      expect(c.routeRequestStatus, RouteRequestStatus.idle);
    });

    test('changing the origin resets it', () async {
      final (:c, :api) = await emptyController();
      await c.requestRoute();
      c.setOrigin('Basra');
      expect(c.routeRequestStatus, RouteRequestStatus.idle);
    });

    test('a stale FAILURE message is cleared by a route change too', () async {
      final (:c, :api) = await emptyController(error: const ApiException('فشل'));
      await c.requestRoute();
      expect(c.routeRequestError, isNotNull);
      c.setDest('Basra');
      expect(c.routeRequestError, isNull);
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester t, TripSearchController c) async {
      await t.pumpWidget(
        ChangeNotifierProvider<TripSearchController>.value(
          value: c,
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: ResultsScreen(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('the action is on the unfiltered empty state', (t) async {
      await pump(t, (await emptyController()).c);
      expect(find.text('أبلغنا أنك تريد هذا المسار'), findsOneWidget);
    });

    testWidgets('and is absent — not disabled — when a filter is active',
        (t) async {
      await pump(t, (await emptyController(driverGender: Gender.female)).c);
      expect(find.text('أبلغنا أنك تريد هذا المسار'), findsNothing);
      expect(find.text('إزالة الفلاتر'), findsOneWidget);
    });

    testWidgets('one tap confirms, and promises no timeframe', (t) async {
      final (:c, :api) = await emptyController();
      await pump(t, c);

      await t.tap(find.text('أبلغنا أنك تريد هذا المسار'));
      // AppButton cross-fades over 120ms; settle past it before reading.
      await t.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('سنخبرك عندما تتوفر رحلات على هذا المسار'), findsOneWidget);
      // The button is REPLACED, so a second tap is not even offered.
      expect(find.text('أبلغنا أنك تريد هذا المسار'), findsNothing);

      // No date, no duration, no «قريباً» — we do not know when, and the
      // confirmation must not imply that we do.
      final confirmation = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(confirmation, isNot(contains('قريباً')));
      expect(confirmation, isNot(contains('خلال')));
      expect(confirmation, isNot(contains('يوم')));
    });

    testWidgets('a failure is shown to the rider', (t) async {
      final (:c, :api) = await emptyController(
        error: const ApiException('تعذّر الاتصال بالخادم.'),
      );
      await pump(t, c);

      await t.tap(find.text('أبلغنا أنك تريد هذا المسار'));
      await t.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('تعذّر الاتصال بالخادم.'), findsOneWidget);
      // ...and the action stays available to retry.
      expect(find.text('أبلغنا أنك تريد هذا المسار'), findsOneWidget);
    });

    testWidgets('no rendered text puts a dot-like glyph beside an Arabic digit',
        (t) async {
      // `٠` IS a dot and `·` is bidi-neutral, so the two fuse and «٣ مقاعد»
      // becomes «٣٠ مقاعد». This screen carries no digits today; the sweep is
      // here so that adding one (a request count, a date) cannot ship broken.
      final (:c, :api) = await emptyController();
      await pump(t, c);
      await t.tap(find.text('أبلغنا أنك تريد هذا المسار'));
      await t.pumpAndSettle(const Duration(milliseconds: 300));

      for (final text in t.widgetList<Text>(find.byType(Text))) {
        final s = text.data;
        if (s == null) continue;
        expect(
          RegExp(r'[·•.]\s*[٠-٩]|[٠-٩]\s*[·•.]').hasMatch(s),
          isFalse,
          reason: 'dot-like glyph next to an Arabic-Indic digit in: "$s"',
        );
      }
    });
  });
}
