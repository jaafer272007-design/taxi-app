import 'package:flutter_test/flutter_test.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:shared/shared.dart';

void main() {
  Map<String, dynamic> base(Map<String, dynamic> extra) => {
        'id': 't1',
        'corridorId': 'c1',
        'departureTime': '2026-07-20T04:30:00.000Z',
        'pricePerSeat': 6000,
        'seatsAvailable': 3,
        'seatsTotal': 4,
        'driverRatingAvg': 4.5,
        ...extra,
      };

  group('TripSummary.fromJson', () {
    test('parses tripType + driverGender', () {
      final t = TripSummary.fromJson(
        base({'tripType': 'WOMEN_FAMILY', 'driverGender': 'FEMALE'}),
      );
      expect(t.tripType, TripType.womenFamily);
      expect(t.driverGender, Gender.female);
    });

    test('defaults tripType to general and driverGender to null', () {
      final t = TripSummary.fromJson(base(const {}));
      expect(t.tripType, TripType.general);
      expect(t.driverGender, isNull);
    });
  });

  test('TripTypeApi.apiValue round-trips', () {
    expect(TripType.general.apiValue, 'GENERAL');
    expect(TripType.womenFamily.apiValue, 'WOMEN_FAMILY');
  });
}
