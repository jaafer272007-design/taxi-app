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
}
