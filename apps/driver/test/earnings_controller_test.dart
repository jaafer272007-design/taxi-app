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

  test('an API error surfaces as the Arabic error message', () async {
    final api = FakeDriverTripApi()
      ..earningsError = const ApiException('تعذّر الاتصال بالخادم.', isNetwork: true);
    final c = EarningsController(api: api);
    await c.load();

    expect(c.status, EarningsStatus.error);
    expect(c.error, 'تعذّر الاتصال بالخادم.');
  });
}
