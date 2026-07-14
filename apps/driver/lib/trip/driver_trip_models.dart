/// A corridor (one direction, e.g. Najaf → Karbala). GET /corridors returns both
/// directions; `active: false` corridors can't be posted on.
class Corridor {
  const Corridor({
    required this.id,
    required this.originCity,
    required this.destCity,
    required this.active,
    required this.pricePerSeat,
  });

  final String id;
  final String originCity;
  final String destCity;
  final bool active;
  final int pricePerSeat;

  factory Corridor.fromJson(Map<String, dynamic> json) => Corridor(
        id: json['id'] as String,
        originCity: json['originCity'] as String,
        destCity: json['destCity'] as String,
        active: json['active'] as bool? ?? true,
        pricePerSeat: (json['pricePerSeat'] as num).toInt(),
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
  });

  final String id;
  final String corridorId;
  final DateTime departureTime;
  final bool departNow;
  final int seatsTotal;
  final int seatsAvailable;
  final int pricePerSeat;
  final TripStatus status;

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
class TripBooking {
  const TripBooking({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.seatCount,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.fare,
    required this.status,
  });

  final String id;
  final String riderId;
  final String? riderName;
  final int seatCount;
  final String pickupLabel;
  final String dropoffLabel;
  final int fare;
  final BookingStatus status;

  TripBooking copyWith({BookingStatus? status}) => TripBooking(
        id: id,
        riderId: riderId,
        riderName: riderName,
        seatCount: seatCount,
        pickupLabel: pickupLabel,
        dropoffLabel: dropoffLabel,
        fare: fare,
        status: status ?? this.status,
      );

  factory TripBooking.fromJson(Map<String, dynamic> json) => TripBooking(
        id: json['id'] as String,
        riderId: json['riderId'] as String,
        riderName: json['riderName'] as String?,
        seatCount: (json['seatCount'] as num?)?.toInt() ?? 1,
        pickupLabel: json['pickupLabel'] as String? ?? '',
        dropoffLabel: json['dropoffLabel'] as String? ?? '',
        fare: (json['fare'] as num?)?.toInt() ?? 0,
        status: bookingStatusFrom(json['status'] as String?),
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
