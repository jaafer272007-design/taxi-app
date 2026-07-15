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
  });

  test('TripTypeApi.apiValue', () {
    expect(TripType.general.apiValue, 'GENERAL');
    expect(TripType.womenFamily.apiValue, 'WOMEN_FAMILY');
  });
}
