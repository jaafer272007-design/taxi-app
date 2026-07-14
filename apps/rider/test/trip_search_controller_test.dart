import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider/trip/trip_search_controller.dart';

import 'support/trip_fakes.dart';
import 'package:shared/shared.dart';

void main() {
  late FakeTripApi api;
  TripSearchController make() => TripSearchController(api: api);

  setUp(() => api = FakeTripApi());

  group('corridors', () {
    test('ensureCorridorsLoaded loads and default-selects the first', () async {
      api.corridors = const [najafKarbala, karbalaNajaf];
      final c = make();
      await c.ensureCorridorsLoaded();
      expect(c.corridors.length, 2);
      expect(c.corridor?.id, 'c1');
      expect(c.corridorsError, isNull);
    });

    test('is idempotent (loads once)', () async {
      api.corridors = const [najafKarbala];
      final c = make();
      await c.ensureCorridorsLoaded();
      await c.ensureCorridorsLoaded();
      expect(api.getCorridorsCalls, 1);
    });

    test('error surfaces a message', () async {
      api.corridorsError = const ApiException('تعذّر تحميل المسارات.');
      final c = make();
      await c.ensureCorridorsLoaded();
      expect(c.corridorsError, 'تعذّر تحميل المسارات.');
      expect(c.corridor, isNull);
    });

    test('swapDirection selects the reverse corridor', () async {
      api.corridors = const [najafKarbala, karbalaNajaf];
      final c = make();
      await c.ensureCorridorsLoaded();
      expect(c.corridor?.id, 'c1');
      c.swapDirection();
      expect(c.corridor?.id, 'c2');
      c.swapDirection();
      expect(c.corridor?.id, 'c1');
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

    test('no-op without a selected corridor', () async {
      final c = make();
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
}
