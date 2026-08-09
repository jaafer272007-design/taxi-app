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

/// The car the rider will be looking for, as GET /bookings/mine returns it.
///
/// Not new information: the rider already saw all of this in search, which is
/// how they chose. It travels with the booking so «شارك رحلتي» can name the
/// vehicle without a second request the rider would have to wait for.
class BookingVehicle {
  const BookingVehicle({this.make, this.model, this.plate, this.color});

  final String? make;
  final String? model;

  /// The plate, exactly as registered — an identifier to be matched against a
  /// metal plate, so it is never converted to Arabic-Indic digits.
  final String? plate;
  final String? color;

  factory BookingVehicle.fromJson(Map<String, dynamic> json) => BookingVehicle(
        make: json['make'] as String?,
        model: json['model'] as String?,
        plate: json['plate'] as String?,
        color: json['color'] as String?,
      );
}

/// Trip info attached to a booking in GET /bookings/mine.
class BookingTrip {
  const BookingTrip({
    required this.id,
    required this.departureTime,
    this.corridor,
    this.status,
  });

  final String id;
  final DateTime departureTime;
  final BookingCorridor? corridor;

  /// The TRIP's state (`OPEN` / `LOCKED` / `EN_ROUTE` / …), which is a
  /// different question from the booking's own status.
  ///
  /// Kept as the raw server string rather than an enum because the rider app
  /// asks exactly one thing of it — [isEnRoute] — and an enum here would be a
  /// third place that has to learn about every new trip state.
  final String? status;

  /// The ride is actually happening right now.
  ///
  /// This is a STATUS question, never a clock question. `departureTime` has
  /// passed for every «الآن» trip the instant it is posted, so any hand-rolled
  /// `departureTime < now` here would light the emergency action up on trips
  /// that have not moved — the same trap that made departNow bookings vanish
  /// (CLAUDE.md).
  bool get isEnRoute => status == 'EN_ROUTE';

  factory BookingTrip.fromJson(Map<String, dynamic> json) => BookingTrip(
        id: json['id'] as String,
        departureTime: DateTime.parse(json['departureTime'] as String),
        status: json['status'] as String?,
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
    this.vehicle,
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

  /// The car, for «شارك رحلتي». Null on responses that carry no trip.
  final BookingVehicle? vehicle;

  /// Everything «شارك رحلتي» needs, assembled in one place.
  ///
  /// Null when the booking arrived without its trip (the POST /bookings and
  /// cancel responses), because a share with no route and no time is not worth
  /// offering — the caller draws no action rather than a broken one.
  TripShareDetails? get shareDetails {
    final t = trip;
    if (t == null) return null;
    return TripShareDetails(
      originCity: t.corridor?.originCity,
      destCity: t.corridor?.destCity,
      departureTime: t.departureTime,
      seatCount: seatCount,
      driverName: driverName,
      vehicleMake: vehicle?.make,
      vehicleModel: vehicle?.model,
      vehicleColor: vehicle?.color,
      plate: vehicle?.plate,
    );
  }

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
        vehicle: json['vehicle'] == null
            ? null
            : BookingVehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
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
        vehicle: vehicle,
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

/// Whether this rider may create a new booking at all right now.
///
/// A rider who repeatedly books and does not turn up is blocked from making
/// NEW bookings for a cooling-off period; the bookings they already hold are
/// untouched. The server is the gate (`POST /bookings` refuses regardless);
/// this exists so the app can say so BEFORE the rider picks seats and points
/// and only then meets a 403.
class BookingEligibility {
  const BookingEligibility({
    required this.blocked,
    this.blockedUntil,
    this.noShowCount = 0,
    this.message,
  });

  /// Not blocked — the state for very nearly every rider, and the default the
  /// app assumes when the check itself fails (see [BookingApi.eligibility]).
  static const ok = BookingEligibility(blocked: false);

  final bool blocked;

  /// When the block lifts. The app formats it in Arabic-Indic numerals; the
  /// server sends an instant, not a rendered string, precisely so it can.
  final DateTime? blockedUntil;

  /// Non-voided no-shows inside the policy window.
  final int noShowCount;

  /// The server's own Arabic explanation, shown verbatim when present so the
  /// wording lives in one place.
  final String? message;

  factory BookingEligibility.fromJson(Map<String, dynamic> json) =>
      BookingEligibility(
        blocked: json['blocked'] as bool? ?? false,
        blockedUntil: json['blockedUntil'] == null
            ? null
            : DateTime.parse(json['blockedUntil'] as String),
        noShowCount: (json['noShowCount'] as num?)?.toInt() ?? 0,
        message: json['message'] as String?,
      );
}
