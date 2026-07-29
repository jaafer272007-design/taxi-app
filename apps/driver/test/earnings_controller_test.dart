import 'package:driver/earnings/earnings_controller.dart';
import 'package:driver/trip/driver_trip_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

void main() {
  test('loads today + all-time totals and the all-time breakdown', () async {
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': const DriverEarnings(total: 18000, records: []),
        'all': DriverEarnings(total: 96000, records: [
          earningsRecordFixture(id: 'e1', amount: 12000),
          earningsRecordFixture(id: 'e2', amount: 6000),
        ]),
      };
    final c = EarningsController(api: api);
    await c.load();

    expect(c.status, EarningsStatus.loaded);
    expect(c.todayTotal, 18000);
    expect(c.allTimeTotal, 96000);
    expect(c.records.map((r) => r.id), ['e1', 'e2']);
    expect(c.isEmpty, isFalse);
    expect(c.hasLoaded, isTrue);
  });

  test('empty earnings → zero totals and an empty breakdown', () async {
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': const DriverEarnings(total: 0, records: []),
        'all': const DriverEarnings(total: 0, records: []),
      };
    final c = EarningsController(api: api);
    await c.load();

    expect(c.todayTotal, 0);
    expect(c.allTimeTotal, 0);
    expect(c.isEmpty, isTrue);
  });

  test('the ledger groups into Baghdad days, newest first, and each day\'s '
      'total is the sum of its own rows', () async {
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': DriverEarnings(total: 18000, records: [
          earningsRecordFixture(id: 'e1', amount: 12000, dayUtc: 20),
        ]),
        'all': DriverEarnings(total: 48000, records: [
          // Deliberately unsorted — the API guarantees no order.
          earningsRecordFixture(
              id: 'e2', amount: 6000, dayUtc: 19, hourUtc: 4),
          earningsRecordFixture(
              id: 'e1', amount: 12000, dayUtc: 20, hourUtc: 6),
          earningsRecordFixture(
              id: 'e4', amount: 24000, dayUtc: 19, hourUtc: 10),
          earningsRecordFixture(
              id: 'e3', amount: 6000, dayUtc: 20, hourUtc: 9),
        ]),
      };
    final c = EarningsController(api: api);
    await c.load();

    expect(c.days.map((d) => d.date), [
      DateTime.utc(2026, 7, 20),
      DateTime.utc(2026, 7, 19),
    ]);
    // Newest row first inside a day.
    expect(c.days.first.records.map((r) => r.id), ['e3', 'e1']);
    // A header's figure is its own rows added up — never a separate field.
    expect(c.days.first.total, 18000);
    expect(c.days.last.total, 30000);
    expect(c.days.fold<int>(0, (s, d) => s + d.total), c.allTimeTotal);
  });

  test('a record after 21:00 UTC belongs to the NEXT Baghdad day', () async {
    // Iraq is UTC+3, so 22:30 UTC on the 19th is 01:30 on the 20th locally.
    // Grouping on the raw UTC date would file this under the wrong day and the
    // driver's daily totals would silently disagree with their cash.
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': const DriverEarnings(total: 0, records: []),
        'all': DriverEarnings(total: 6000, records: [
          earningsRecordFixture(
              id: 'e1', amount: 6000, dayUtc: 19, hourUtc: 22, minute: 30),
        ]),
      };
    final c = EarningsController(api: api);
    await c.load();

    expect(c.days.single.date, DateTime.utc(2026, 7, 20));
  });

  test('trip counts come from each range\'s own rows', () async {
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': DriverEarnings(total: 18000, records: [
          earningsRecordFixture(id: 'e1', amount: 12000),
          earningsRecordFixture(id: 'e2', amount: 6000),
        ]),
        'all': DriverEarnings(total: 96000, records: [
          earningsRecordFixture(id: 'e1', amount: 12000),
          earningsRecordFixture(id: 'e2', amount: 6000),
          earningsRecordFixture(id: 'e3', amount: 78000, dayUtc: 18),
        ]),
      };
    final c = EarningsController(api: api);
    await c.load();

    // Today's count is the today RANGE's row count, not a client-side filter of
    // the all-time list against the phone clock.
    expect(c.todayTripCount, 2);
    expect(c.tripCount, 3);
  });

  test('an API error surfaces as the Arabic error message', () async {
    final api = FakeDriverTripApi()
      ..earningsError = const ApiException('تعذّر الاتصال بالخادم.', isNetwork: true);
    final c = EarningsController(api: api);
    await c.load();

    expect(c.status, EarningsStatus.error);
    expect(c.error, 'تعذّر الاتصال بالخادم.');
  });
}
