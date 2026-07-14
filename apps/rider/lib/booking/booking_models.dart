/// A door-to-door point the rider marks (a label + coordinates). The map picker
/// is Phase 2 (PostGIS); for now coordinates default to the city centre and the
/// rider types the label.
class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, required this.label});

  final double lat;
  final double lng;
  final String label;

  GeoPoint copyWith({double? lat, double? lng, String? label}) => GeoPoint(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        label: label ?? this.label,
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'label': label};
}

/// Approximate city-centre coordinates used as a sensible default pickup/dropoff
/// until the map picker lands (Phase 2). Falls back to Najaf for unknown cities.
GeoPoint cityCenter(String? city, {String label = ''}) {
  switch (city) {
    case 'Karbala':
      return GeoPoint(lat: 32.6160, lng: 44.0242, label: label);
    case 'Najaf':
    default:
      return GeoPoint(lat: 31.9990, lng: 44.3148, label: label);
  }
}

/// Lifecycle state of a seat booking (mirrors the backend `BookingStatus` enum).
enum BookingStatus { confirmed, onboard, completed, cancelled, noShow, unknown }

BookingStatus bookingStatusFrom(String? raw) => switch (raw) {
      'CONFIRMED' => BookingStatus.confirmed,
      'ONBOARD' => BookingStatus.onboard,
      'COMPLETED' => BookingStatus.completed,
      'CANCELLED' => BookingStatus.cancelled,
      'NO_SHOW' => BookingStatus.noShow,
      _ => BookingStatus.unknown,
    };

/// Corridor endpoints, nested under a booking's trip in GET /bookings/mine.
class BookingCorridor {
  const BookingCorridor({required this.originCity, required this.destCity});

  final String originCity;
  final String destCity;

  factory BookingCorridor.fromJson(Map<String, dynamic> json) => BookingCorridor(
        originCity: json['originCity'] as String,
        destCity: json['destCity'] as String,
      );
}

/// Trip info attached to a booking in GET /bookings/mine.
class BookingTrip {
  const BookingTrip({
    required this.id,
    required this.departureTime,
    this.corridor,
  });

  final String id;
  final DateTime departureTime;
  final BookingCorridor? corridor;

  factory BookingTrip.fromJson(Map<String, dynamic> json) => BookingTrip(
        id: json['id'] as String,
        departureTime: DateTime.parse(json['departureTime'] as String),
        corridor: json['corridor'] == null
            ? null
            : BookingCorridor.fromJson(json['corridor'] as Map<String, dynamic>),
      );
}

/// A seat booking. GET /bookings/mine returns the [trip] + [upcoming] flag;
/// POST /bookings and cancel return the booking alone (both null then).
class Booking {
  const Booking({
    required this.id,
    required this.seatCount,
    required this.fare,
    required this.status,
    required this.pickupLabel,
    required this.dropoffLabel,
    this.trip,
    this.upcoming,
  });

  final String id;
  final int seatCount;
  final int fare;
  final BookingStatus status;
  final String pickupLabel;
  final String dropoffLabel;
  final BookingTrip? trip;

  /// Server-computed: is the trip's departure still in the future? Null when the
  /// response omits the trip (POST /bookings, cancel).
  final bool? upcoming;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        seatCount: (json['seatCount'] as num).toInt(),
        fare: (json['fare'] as num).toInt(),
        status: bookingStatusFrom(json['status'] as String?),
        pickupLabel: (json['pickupLabel'] as String?) ?? '',
        dropoffLabel: (json['dropoffLabel'] as String?) ?? '',
        trip: json['trip'] == null
            ? null
            : BookingTrip.fromJson(json['trip'] as Map<String, dynamic>),
        upcoming: json['upcoming'] as bool?,
      );
}
