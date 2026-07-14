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
