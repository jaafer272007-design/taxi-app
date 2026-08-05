import 'package:shared/shared.dart';

/// A door-to-door point the rider marks (a label + coordinates), as it goes
/// over the wire to POST /bookings.
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

  /// The shared map/location type. Kept as a conversion rather than a swap so
  /// [toJson] stays the one thing that defines the wire shape.
  LocationPoint get asLocationPoint =>
      LocationPoint(lat: lat, lng: lng, label: label);
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

/// The driver's phone number for a trip the rider has booked
/// (GET /trips/:id/contacts).
///
/// Never present on a search result or anywhere else: the server returns a
/// number only to a rider holding a live booking on that trip, so there is no
/// screen before the booking that could show one.
class TripContact {
  const TripContact({
    required this.userId,
    required this.name,
    required this.phone,
    required this.bookingId,
  });

  final String userId;
  final String? name;

  /// E.164, e.g. `+9647701234567`.
  final String phone;
  final String bookingId;

  factory TripContact.fromJson(Map<String, dynamic> json) => TripContact(
        userId: json['userId'] as String,
        name: json['name'] as String?,
        phone: json['phone'] as String? ?? '',
        bookingId: json['bookingId'] as String? ?? '',
      );
}

/// A seat booking. GET /bookings/mine returns the [trip] + [upcoming] flag;
/// POST /bookings and cancel return the booking alone (both null then).
///
/// [pickup] / [dropoff] carry coordinates as well as labels, so the rider can
/// see the points they chose on a map — a reverse-geocoded name is how they
/// recognise the place, but only the point proves it is the right one.
class Booking {
  const Booking({
    required this.id,
    required this.seatCount,
    required this.fare,
    required this.status,
    required this.pickup,
    required this.dropoff,
    this.trip,
    this.upcoming,
    this.driverUserId,
    this.driverName,
    this.ratable = false,
    this.ratedDriver = false,
  });

  final String id;
  final int seatCount;
  final int fare;
  final BookingStatus status;
  final LocationPoint pickup;
  final LocationPoint dropoff;
  final BookingTrip? trip;

  /// Server-computed: does this booking still belong under «قادمة»? Null when
  /// the response omits the trip (POST /bookings, cancel).
  ///
  /// A STATUS question, not a clock one — a completed booking is past even if
  /// its trip had been scheduled for tonight. The rule lives server-side in
  /// `booking-lifecycle.ts`; the app must not re-derive it, or the two drift
  /// and the drift is invisible until someone completes a trip early.
  final bool? upcoming;

  /// The driver's USER id — who a rating is addressed to. Null on responses
  /// that carry no trip.
  final String? driverUserId;

  /// The driver's display name, for the rate sheet.
  final String? driverName;

  /// The ride actually happened, so a rating is allowed. Server-computed to
  /// stay in step with what `POST /ratings` will accept: an action the UI
  /// offers and the server refuses is worse than no action.
  final bool ratable;

  /// This rider has already rated this driver for this trip.
  final bool ratedDriver;

  /// Show a rate action for this booking.
  bool get canRate => ratable && !ratedDriver && driverUserId != null;

  String get pickupLabel => pickup.label;
  String get dropoffLabel => dropoff.label;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        seatCount: (json['seatCount'] as num).toInt(),
        fare: (json['fare'] as num).toInt(),
        status: bookingStatusFrom(json['status'] as String?),
        pickup: _pointFrom(json, 'pickup'),
        dropoff: _pointFrom(json, 'dropoff'),
        trip: json['trip'] == null
            ? null
            : BookingTrip.fromJson(json['trip'] as Map<String, dynamic>),
        upcoming: json['upcoming'] as bool?,
        driverUserId: json['driverUserId'] as String?,
        driverName: json['driverName'] as String?,
        ratable: json['ratable'] as bool? ?? false,
        ratedDriver: json['ratedDriver'] as bool? ?? false,
      );

  Booking copyWith({bool? ratedDriver}) => Booking(
        id: id,
        seatCount: seatCount,
        fare: fare,
        status: status,
        pickup: pickup,
        dropoff: dropoff,
        trip: trip,
        upcoming: upcoming,
        driverUserId: driverUserId,
        driverName: driverName,
        ratable: ratable,
        ratedDriver: ratedDriver ?? this.ratedDriver,
      );
}

/// Read `<prefix>Lat` / `<prefix>Lng` / `<prefix>Label` into a [LocationPoint].
/// Missing coordinates become 0,0; callers check
/// [LocationPoint.hasCoordinates] rather than opening a map on Null Island.
LocationPoint _pointFrom(Map<String, dynamic> json, String prefix) =>
    LocationPoint(
      lat: (json['${prefix}Lat'] as num?)?.toDouble() ?? 0,
      lng: (json['${prefix}Lng'] as num?)?.toDouble() ?? 0,
      label: json['${prefix}Label'] as String? ?? '',
    );
