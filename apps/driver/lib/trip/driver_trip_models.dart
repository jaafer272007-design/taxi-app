import 'package:shared/shared.dart';

/// A corridor (one direction, e.g. Najaf → Karbala). GET /corridors returns both
/// directions; `active: false` corridors can't be posted on.
///
/// The corridor does NOT set the fare — the driver does, when posting. What the
/// admin publishes here is a suggestion ([suggestedPricePerSeat]) and the band
/// the driver's price has to land in ([minPricePerSeat] … [maxPricePerSeat]).
/// The backend guarantees `0 < min <= suggested <= max`.
class Corridor {
  const Corridor({
    required this.id,
    required this.originCity,
    required this.destCity,
    required this.active,
    required this.suggestedPricePerSeat,
    required this.minPricePerSeat,
    required this.maxPricePerSeat,
  });

  final String id;
  final String originCity;
  final String destCity;
  final bool active;

  /// The usual price on this route, in IQD — what the post-a-trip form prefills.
  final int suggestedPricePerSeat;

  /// Inclusive bounds on what the driver may charge per seat, in IQD.
  final int minPricePerSeat;
  final int maxPricePerSeat;

  /// True when the admin pinned this route to a single price (min == max), so
  /// the form can say "ثابت" instead of offering a range.
  bool get isFixedPrice => minPricePerSeat == maxPricePerSeat;

  factory Corridor.fromJson(Map<String, dynamic> json) => Corridor(
        id: json['id'] as String,
        originCity: json['originCity'] as String,
        destCity: json['destCity'] as String,
        active: json['active'] as bool? ?? true,
        suggestedPricePerSeat: (json['suggestedPricePerSeat'] as num).toInt(),
        minPricePerSeat: (json['minPricePerSeat'] as num).toInt(),
        maxPricePerSeat: (json['maxPricePerSeat'] as num).toInt(),
      );
}

/// Lifecycle state of a trip (mirrors the backend `TripStatus` enum).
enum TripStatus { open, locked, enRoute, completed, settled, cancelled, unknown }

TripStatus tripStatusFrom(String? raw) => switch (raw) {
      'OPEN' => TripStatus.open,
      'LOCKED' => TripStatus.locked,
      'EN_ROUTE' => TripStatus.enRoute,
      'COMPLETED' => TripStatus.completed,
      'SETTLED' => TripStatus.settled,
      'CANCELLED' => TripStatus.cancelled,
      _ => TripStatus.unknown,
    };

/// Trip audience (mirrors the backend `TripType` enum). `womenFamily` trips only
/// accept female riders (a woman may book extra seats for family); any driver
/// may post either type.
enum TripType { general, womenFamily }

/// Parse a backend trip-type string; unknown / null → [TripType.general]
/// (matches the backend default).
TripType tripTypeFrom(String? raw) =>
    raw == 'WOMEN_FAMILY' ? TripType.womenFamily : TripType.general;

extension TripTypeApi on TripType {
  /// The wire value the backend expects (`GENERAL` / `WOMEN_FAMILY`).
  String get apiValue =>
      this == TripType.womenFamily ? 'WOMEN_FAMILY' : 'GENERAL';
}

/// A driver's own posted trip (POST /trips + GET /trips/mine). Carries no nested
/// corridor — join by [corridorId] against GET /corridors for city names.
class DriverTrip {
  const DriverTrip({
    required this.id,
    required this.corridorId,
    required this.departureTime,
    required this.departNow,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.pricePerSeat,
    required this.status,
    required this.catchableUntil,
    this.tripType = TripType.general,
  });

  final String id;
  final String corridorId;
  final DateTime departureTime;
  final bool departNow;

  /// When riders stop being able to find and book this trip.
  ///
  /// Server-computed (GET /trips/mine). For a scheduled trip it equals
  /// [departureTime]; for a «الآن» trip it is departure plus the validity
  /// window. Deliberately NOT derived here — the window length is a server
  /// rule, and a second copy of it in the app is exactly how the two sides
  /// drifted apart and made departNow trips invisible to riders.
  final DateTime catchableUntil;
  final int seatsTotal;
  final int seatsAvailable;
  final int pricePerSeat;
  final TripStatus status;
  final TripType tripType;

  int get seatsBooked => seatsTotal - seatsAvailable;

  DriverTrip copyWith({TripStatus? status}) => DriverTrip(
        id: id,
        corridorId: corridorId,
        departureTime: departureTime,
        departNow: departNow,
        seatsTotal: seatsTotal,
        seatsAvailable: seatsAvailable,
        pricePerSeat: pricePerSeat,
        status: status ?? this.status,
        catchableUntil: catchableUntil,
        tripType: tripType,
      );

  factory DriverTrip.fromJson(Map<String, dynamic> json) => DriverTrip(
        id: json['id'] as String,
        corridorId: json['corridorId'] as String,
        departureTime: DateTime.parse(json['departureTime'] as String),
        departNow: json['departNow'] as bool? ?? false,
        seatsTotal: (json['seatsTotal'] as num).toInt(),
        seatsAvailable: (json['seatsAvailable'] as num).toInt(),
        pricePerSeat: (json['pricePerSeat'] as num).toInt(),
        status: tripStatusFrom(json['status'] as String?),
        // Falling back to departureTime is the conservative reading: it is
        // exactly right for a scheduled trip, and merely understates the window
        // for a departNow one, so an older API can never make the app claim a
        // trip is live for longer than it is.
        catchableUntil: DateTime.parse(
          (json['catchableUntil'] ?? json['departureTime']) as String,
        ),
        tripType: tripTypeFrom(json['tripType'] as String?),
      );
}

/// Lifecycle state of a single seat booking (mirrors backend `BookingStatus`).
enum BookingStatus { confirmed, onboard, completed, cancelled, noShow, unknown }

BookingStatus bookingStatusFrom(String? raw) => switch (raw) {
      'CONFIRMED' => BookingStatus.confirmed,
      'ONBOARD' => BookingStatus.onboard,
      'COMPLETED' => BookingStatus.completed,
      'CANCELLED' => BookingStatus.cancelled,
      'NO_SHOW' => BookingStatus.noShow,
      _ => BookingStatus.unknown,
    };

/// One booking on the driver's own trip (GET /trips/:id/bookings). The rider's
/// [riderName] is resolved server-side; [riderId] is the target for rating.
///
/// Carries the pickup/dropoff as [LocationPoint]s, coordinates included: a
/// neighbourhood name tells the driver roughly where to head, but only a point
/// can be shown on a map or handed to a navigation app — and completing a
/// door-to-door pickup needs the latter.
///
/// Deliberately NO phone number. The rider's comes from
/// `GET /trips/:id/contacts` alone, which is the only endpoint that returns one.
class TripBooking {
  const TripBooking({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.seatCount,
    required this.pickup,
    required this.dropoff,
    required this.fare,
    required this.status,
  });

  final String id;
  final String riderId;
  final String? riderName;
  final int seatCount;
  final LocationPoint pickup;
  final LocationPoint dropoff;
  final int fare;
  final BookingStatus status;

  String get pickupLabel => pickup.label;
  String get dropoffLabel => dropoff.label;

  TripBooking copyWith({BookingStatus? status}) => TripBooking(
        id: id,
        riderId: riderId,
        riderName: riderName,
        seatCount: seatCount,
        pickup: pickup,
        dropoff: dropoff,
        fare: fare,
        status: status ?? this.status,
      );

  factory TripBooking.fromJson(Map<String, dynamic> json) => TripBooking(
        id: json['id'] as String,
        riderId: json['riderId'] as String,
        riderName: json['riderName'] as String?,
        seatCount: (json['seatCount'] as num?)?.toInt() ?? 1,
        pickup: _pointFrom(json, 'pickup'),
        dropoff: _pointFrom(json, 'dropoff'),
        fare: (json['fare'] as num?)?.toInt() ?? 0,
        status: bookingStatusFrom(json['status'] as String?),
      );
}

/// Read `<prefix>Lat` / `<prefix>Lng` / `<prefix>Label` into a [LocationPoint].
///
/// Coordinates default to 0,0 only if an older API omits them entirely; callers
/// check [LocationPoint.hasCoordinates] rather than opening a map on Null
/// Island.
LocationPoint _pointFrom(Map<String, dynamic> json, String prefix) =>
    LocationPoint(
      lat: (json['${prefix}Lat'] as num?)?.toDouble() ?? 0,
      lng: (json['${prefix}Lng'] as num?)?.toDouble() ?? 0,
      label: json['${prefix}Label'] as String? ?? '',
    );

/// One reachable person on a trip (GET /trips/:id/contacts).
///
/// The server returns these ONLY to the trip's driver and to riders holding a
/// live booking on it; everyone else gets 403. The app never decides who may
/// see a number — it asks, and renders what comes back.
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

  /// The booking connecting the caller to this contact — for a driver, which of
  /// their bookings this rider holds.
  final String bookingId;

  factory TripContact.fromJson(Map<String, dynamic> json) => TripContact(
        userId: json['userId'] as String,
        name: json['name'] as String?,
        phone: json['phone'] as String? ?? '',
        bookingId: json['bookingId'] as String? ?? '',
      );
}

/// One cash-collected earnings row (GET /driver/earnings → records[]). Carries
/// only [tripId]/[amount]/[collectedAt] — no route names server-side.
class EarningsRecord {
  const EarningsRecord({
    required this.id,
    required this.tripId,
    required this.amount,
    required this.collectedAt,
  });

  final String id;
  final String tripId;
  final int amount;
  final DateTime collectedAt;

  factory EarningsRecord.fromJson(Map<String, dynamic> json) => EarningsRecord(
        id: json['id'] as String,
        tripId: json['tripId'] as String,
        amount: (json['amount'] as num).toInt(),
        collectedAt: DateTime.parse(json['collectedAt'] as String),
      );
}

/// One Baghdad calendar day of the earnings ledger.
///
/// The ledger is grouped by day so every figure on the screen reconciles: a
/// day's [total] is the sum of the rows printed under it, and the sum of the
/// days is the all-time total. A driver handling cash has to be able to check
/// the app against what is in their pocket, and that only works if the arithmetic
/// is visible.
class EarningsDay {
  const EarningsDay({
    required this.date,
    required this.records,
    required this.total,
  });

  /// Midnight of the Baghdad calendar day these records fall on.
  final DateTime date;

  /// The day's records, newest first.
  final List<EarningsRecord> records;

  /// Sum of [records] — never taken from anywhere else.
  final int total;
}

/// A driver's earnings for one range (GET /driver/earnings?range=today|all).
class DriverEarnings {
  const DriverEarnings({required this.total, required this.records});

  final int total;
  final List<EarningsRecord> records;

  factory DriverEarnings.fromJson(Map<String, dynamic> json) => DriverEarnings(
        total: (json['total'] as num?)?.toInt() ?? 0,
        records: ((json['records'] as List<dynamic>?) ?? const [])
            .map((e) => EarningsRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
