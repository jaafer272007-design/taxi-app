import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:rider/trip/trip_search_controller.dart';

import 'support/trip_fakes.dart';
import 'package:shared/shared.dart';

void main() {
  late FakeTripApi api;
  TripSearchController make() => TripSearchController(api: api);

  setUp(() => api = FakeTripApi());

  group('route (from/to cities)', () {
    test('ensureCorridorsLoaded defaults from/to to the first corridor', () async {
      api.corridors = const [najafKarbala, karbalaNajaf];
      final c = make();
      await c.ensureCorridorsLoaded();
      expect(c.corridors.length, 2);
      expect(c.origin, 'Najaf');
      expect(c.dest, 'Karbala');
      expect(c.matchedCorridor?.id, 'c1');
      expect(c.canSearch, isTrue);
      expect(c.corridorsError, isNull);
    });

    test('is idempotent (loads once)', () async {
      api.corridors = const [najafKarbala];
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.ensureCorridorsLoaded();
      expect(api.getCorridorsCalls, 1);
    });

    test('error surfaces a message; no cities defaulted', () async {
      api.corridorsError = const ApiException('تعذّر تحميل المسارات.');
      final c = make();
      await c.ensureCorridorsLoaded();
      expect(c.corridorsError, 'تعذّر تحميل المسارات.');
      expect(c.origin, isNull);
      expect(c.dest, isNull);
    });

    test('swapCities swaps from/to and resolves the reverse corridor', () async {
      api.corridors = const [najafKarbala, karbalaNajaf];
      final c = make();
      await c.ensureCorridorsLoaded();
      expect(c.matchedCorridor?.id, 'c1');
      c.swapCities();
      expect(c.origin, 'Karbala');
      expect(c.dest, 'Najaf');
      expect(c.matchedCorridor?.id, 'c2');
    });

    test('a pair with no corridor → search is empty, never hits the API',
        () async {
      api.corridors = const [najafKarbala]; // only Najaf→Karbala is served
      final c = make();
      await c.ensureCorridorsLoaded();
      c.setOrigin('Baghdad');
      c.setDest('Basra');
      expect(c.matchedCorridor, isNull);
      expect(c.canSearch, isTrue); // distinct cities, so searchable...

      await c.search();
      expect(c.status, TripSearchStatus.empty); // ...but no corridor → empty
      expect(api.searchCalls, 0);
      expect(c.error, isNull);
    });
  });

  group('search', () {
    test('results → status results, sorted by departure time', () async {
      api.corridors = const [najafKarbala];
      api.searchResults = [
        tripFixture(id: 'late', hourUtc: 6),
        tripFixture(id: 'early', hourUtc: 4),
      ];
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();
      expect(c.status, TripSearchStatus.results);
      expect(c.results.first.id, 'early');
      expect(c.results.last.id, 'late');
    });

    test('no results → status empty', () async {
      api.corridors = const [najafKarbala];
      api.searchResults = const [];
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();
      expect(c.status, TripSearchStatus.empty);
    });

    test('error → status error with message', () async {
      api.corridors = const [najafKarbala];
      api.searchError = const ApiException('تعذّر الاتصال بالخادم.');
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();
      expect(c.status, TripSearchStatus.error);
      expect(c.error, 'تعذّر الاتصال بالخادم.');
    });

    test('no-op when no cities are chosen', () async {
      final c = make(); // corridors not loaded → origin/dest null → canSearch false
      await c.search();
      expect(c.status, TripSearchStatus.initial);
      expect(api.searchCalls, 0);
    });
  });

  test('date and time window setters', () async {
    api.corridors = const [najafKarbala];
    final c = make();
    await c.ensureCorridorsLoaded();

    c.setDate(DateTime(2026, 7, 20));
    expect(c.date, DateTime(2026, 7, 20));

    c.setTimeWindow(const TimeOfDay(hour: 6, minute: 0), const TimeOfDay(hour: 12, minute: 0));
    expect(c.hasTimeWindow, isTrue);

    c.clearTimeWindow();
    expect(c.hasTimeWindow, isFalse);
  });

  group('filters', () {
    test('default: no active filters, search passes null filters', () async {
      api.corridors = const [najafKarbala];
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();

      expect(c.hasActiveFilters, isFalse);
      expect(api.lastTripType, isNull);
      expect(api.lastDriverGender, isNull);
    });

    test('setTripType / setDriverGender map into the search query', () async {
      api.corridors = const [najafKarbala];
      final c = make();
      await c.ensureCorridorsLoaded();

      c.setTripType(TripType.womenFamily);
      c.setDriverGender(Gender.female);
      expect(c.hasActiveFilters, isTrue);

      await c.search();
      expect(api.lastTripType, TripType.womenFamily);
      expect(api.lastDriverGender, Gender.female);
    });

    test('a female-driver filter that yields no rows is empty, not an error',
        () async {
      api.corridors = const [najafKarbala];
      api.searchResults = const []; // female drivers are rare → empty
      final c = make();
      await c.ensureCorridorsLoaded();
      c.setDriverGender(Gender.female);
      await c.search();

      expect(c.status, TripSearchStatus.empty);
      expect(c.error, isNull);
    });

    test('clearFilters resets both filters', () async {
      api.corridors = const [najafKarbala];
      final c = make();
      await c.ensureCorridorsLoaded();
      c.setTripType(TripType.general);
      c.setDriverGender(Gender.male);
      expect(c.hasActiveFilters, isTrue);

      c.clearFilters();
      expect(c.hasActiveFilters, isFalse);
      expect(c.tripType, isNull);
      expect(c.driverGender, isNull);
    });
  });

  group('sort (each driver sets their own price, so cheapest is a real question)',
      () {
    // Three trips on ONE route at three prices — impossible before drivers set
    // their own. Departure order and price order are deliberately opposites.
    void seed() {
      api.corridors = const [najafKarbala];
      api.searchResults = [
        tripFixture(id: 'early_dear', hourUtc: 4, price: 12000),
        tripFixture(id: 'mid', hourUtc: 5, price: 9000),
        tripFixture(id: 'late_cheap', hourUtc: 6, price: 6000),
      ];
    }

    test('defaults to departure order', () async {
      seed();
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();

      expect(c.sort, TripSort.departure);
      expect(c.results.map((t) => t.id), ['early_dear', 'mid', 'late_cheap']);
    });

    test('sorting by price reorders cheapest first', () async {
      seed();
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();

      c.setSort(TripSort.price);

      expect(c.results.map((t) => t.id), ['late_cheap', 'mid', 'early_dear']);
    });

    test('re-sorting costs no round trip', () async {
      seed();
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();
      final callsAfterSearch = api.searchCalls;

      c.setSort(TripSort.price);
      c.setSort(TripSort.departure);

      expect(api.searchCalls, callsAfterSearch);
    });

    test('a later search keeps the chosen order', () async {
      seed();
      final c = make();
      await c.ensureCorridorsLoaded();
      c.setSort(TripSort.price);

      await c.search();

      expect(c.results.first.id, 'late_cheap');
    });

    test('ties break on the other key, so the order is deterministic', () async {
      api.corridors = const [najafKarbala];
      api.searchResults = [
        tripFixture(id: 'same_price_late', hourUtc: 7, price: 6000),
        tripFixture(id: 'same_price_early', hourUtc: 5, price: 6000),
      ];
      final c = make();
      await c.ensureCorridorsLoaded();
      c.setSort(TripSort.price);
      await c.search();

      expect(c.results.map((t) => t.id), ['same_price_early', 'same_price_late']);
    });

    test('setting the same sort twice notifies once', () async {
      seed();
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();

      var notifications = 0;
      c.addListener(() => notifications++);
      c.setSort(TripSort.price);
      c.setSort(TripSort.price);

      expect(notifications, 1);
    });
  });

  group('default city pair at full-grid scale', () {
    // Every ordered pair of the 18 governorates is now a corridor (306 rows),
    // so the API's first row is alphabetical accident — العمارة→بغداد.
    List<Corridor> fullGrid() => [
          const Corridor(
              id: 'c-amarah',
              originCity: 'Amarah',
              destCity: 'Baghdad',
              suggestedPricePerSeat: 30000),
          najafKarbala,
          karbalaNajaf,
        ];

    test('opens on the flagship pair, not whichever sorts first', () async {
      api.corridors = fullGrid();
      final c = make();

      await c.ensureCorridorsLoaded();

      expect(c.origin, 'Najaf');
      expect(c.dest, 'Karbala');
      expect(c.matchedCorridor, najafKarbala);
    });

    test('falls back to the first corridor when the flagship is absent',
        () async {
      // Deactivating Najaf→Karbala must not strand the form on a blank pair.
      api.corridors = [
        const Corridor(
            id: 'c-amarah',
            originCity: 'Amarah',
            destCity: 'Baghdad',
            suggestedPricePerSeat: 30000),
      ];
      final c = make();

      await c.ensureCorridorsLoaded();

      expect(c.origin, 'Amarah');
      expect(c.dest, 'Baghdad');
      expect(c.canSearch, isTrue);
    });

    test('handles a 306-corridor payload without breaking resolution', () async {
      // Guards the linear scan in matchedCorridor at real size.
      const cities = [
        'Baghdad', 'Basra', 'Najaf', 'Karbala', 'Erbil', 'Mosul',
        'Kirkuk', 'Sulaymaniyah', 'Duhok', 'Ramadi', 'Baqubah', 'Kut',
        'Amarah', 'Nasiriyah', 'Samawah', 'Diwaniyah', 'Hilla', 'Tikrit',
      ];
      final grid = <Corridor>[];
      for (final o in cities) {
        for (final d in cities) {
          if (o == d) continue;
          grid.add(Corridor(
              id: '\$o-\$d',
              originCity: o,
              destCity: d,
              suggestedPricePerSeat: 12000));
        }
      }
      expect(grid, hasLength(306));

      api.corridors = grid;
      final c = make();
      await c.ensureCorridorsLoaded();

      expect(c.corridors, hasLength(306));
      expect(c.origin, 'Najaf');
      expect(c.dest, 'Karbala');

      // Any pair the rider picks resolves — that is the whole point of the grid.
      c.setOrigin('Duhok');
      c.setDest('Basra');
      expect(c.matchedCorridor, isNotNull);
      expect(c.canSearch, isTrue);
    });
  });

  group('background refresh (poll + pull-to-refresh)', () {
    Future<TripSearchController> loaded() async {
      api.corridors = const [najafKarbala];
      api.searchResults = [tripFixture(id: 't1')];
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.search();
      expect(c.status, TripSearchStatus.results);
      return c;
    }

    test('a failed refresh keeps the list and says nothing', () async {
      final c = await loaded();

      api.searchError = const ApiException('لا يوجد اتصال بالإنترنت.');
      await c.refreshSilently();

      // The whole contract of a background refresh: the rider did not ask for
      // it, so it may not take their results away or tell them it failed.
      expect(c.status, TripSearchStatus.results);
      expect(c.results.map((t) => t.id), ['t1']);
      expect(c.error, isNull);
    });

    test('a refresh never shows the loading skeleton', () async {
      final c = await loaded();
      final seen = <TripSearchStatus>[];
      c.addListener(() => seen.add(c.status));

      await c.refreshSilently();

      expect(seen, isNot(contains(TripSearchStatus.loading)),
          reason: 'shimmer every 15 seconds would make the screen unusable');
    });

    test('a refresh picks up a newly posted trip', () async {
      final c = await loaded();

      api.searchResults = [tripFixture(id: 't1'), tripFixture(id: 't2')];
      await c.refreshSilently();

      expect(c.results.map((t) => t.id), ['t1', 't2']);
    });

    test('a visible search still surfaces its error', () async {
      final c = await loaded();

      api.searchError = const ApiException('لا يوجد اتصال بالإنترنت.');
      await c.search();

      expect(c.status, TripSearchStatus.error);
      expect(c.error, 'لا يوجد اتصال بالإنترنت.');
    });

    test('a recovered refresh clears a stale error', () async {
      final c = await loaded();
      api.searchError = const ApiException('لا يوجد اتصال بالإنترنت.');
      await c.search();
      expect(c.error, isNotNull);

      api.searchError = null;
      await c.refreshSilently();

      expect(c.status, TripSearchStatus.results);
      expect(c.error, isNull);
    });
  });
}
