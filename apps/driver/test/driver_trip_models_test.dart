import 'package:driver/trip/driver_trip_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> base(Map<String, dynamic> extra) => {
        'id': 't1',
        'corridorId': 'c1',
        'departureTime': '2026-07-20T04:30:00.000Z',
        'seatsTotal': 4,
        'seatsAvailable': 4,
        'pricePerSeat': 6000,
        'status': 'OPEN',
        ...extra,
      };

  group('DriverTrip.fromJson', () {
    test('parses WOMEN_FAMILY trip type', () {
      final t = DriverTrip.fromJson(base({'tripType': 'WOMEN_FAMILY'}));
      expect(t.tripType, TripType.womenFamily);
    });

    test('defaults to general when absent or unknown', () {
      expect(DriverTrip.fromJson(base(const {})).tripType, TripType.general);
      expect(
        DriverTrip.fromJson(base({'tripType': 'WHATEVER'})).tripType,
        TripType.general,
      );
    });

    test('copyWith preserves the trip type', () {
      final t = DriverTrip.fromJson(base({'tripType': 'WOMEN_FAMILY'}));
      expect(t.copyWith(status: TripStatus.locked).tripType,
          TripType.womenFamily);
    });

    test('takes catchableUntil from the server, not from a local calculation', () {
      // The window length is a SERVER rule. The app must never recompute it —
      // a second copy of the rule is what let search and posting disagree and
      // made every «الآن» trip invisible to riders.
      final t = DriverTrip.fromJson(base({
        'departNow': true,
        'catchableUntil': '2026-07-20T05:00:00.000Z',
      }));

      expect(t.departNow, isTrue);
      expect(t.catchableUntil, DateTime.parse('2026-07-20T05:00:00.000Z'));
    });

    test('falls back to departureTime when the server omits catchableUntil', () {
      // Conservative on purpose: exactly right for a scheduled trip, and it can
      // only ever UNDERstate a departNow window — so an older API cannot make
      // the app claim a trip is live longer than it is.
      final t = DriverTrip.fromJson(base({'departNow': true}));

      expect(t.catchableUntil, DateTime.parse('2026-07-20T04:30:00.000Z'));
    });

    test('copyWith preserves the window', () {
      final t = DriverTrip.fromJson(base({
        'departNow': true,
        'catchableUntil': '2026-07-20T05:00:00.000Z',
      }));

      expect(t.copyWith(status: TripStatus.locked).catchableUntil,
          DateTime.parse('2026-07-20T05:00:00.000Z'));
    });
  });

  test('TripTypeApi.apiValue', () {
    expect(TripType.general.apiValue, 'GENERAL');
    expect(TripType.womenFamily.apiValue, 'WOMEN_FAMILY');
  });
}
