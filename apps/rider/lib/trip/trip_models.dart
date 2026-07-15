import 'package:shared/shared.dart';

/// Trip audience (mirrors the backend `TripType` enum). `womenFamily` trips only
/// accept female riders (a woman may book extra seats for family).
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

/// A corridor (one direction, e.g. Najaf → Karbala). GET /corridors returns both
/// directions as separate rows.
class Corridor {
  const Corridor({
    required this.id,
    required this.originCity,
    required this.destCity,
    required this.pricePerSeat,
  });

  final String id;
  final String originCity;
  final String destCity;
  final int pricePerSeat;

  factory Corridor.fromJson(Map<String, dynamic> json) => Corridor(
        id: json['id'] as String,
        originCity: json['originCity'] as String,
        destCity: json['destCity'] as String,
        pricePerSeat: (json['pricePerSeat'] as num).toInt(),
      );
}

/// Vehicle summary shown on a trip.
class TripVehicle {
  const TripVehicle({
    required this.make,
    required this.model,
    required this.color,
    required this.seats,
  });

  final String make;
  final String model;
  final String color;
  final int seats;

  /// e.g. "Toyota Corolla".
  String get label => '$make $model';

  factory TripVehicle.fromJson(Map<String, dynamic> json) => TripVehicle(
        make: json['make'] as String,
        model: json['model'] as String,
        color: json['color'] as String,
        seats: (json['seats'] as num).toInt(),
      );
}

/// A driver-posted trip as returned by GET /trips/search.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.corridorId,
    required this.departureTime,
    required this.pricePerSeat,
    required this.seatsAvailable,
    required this.seatsTotal,
    required this.driverRatingAvg,
    this.driverName,
    this.driverGender,
    this.vehicle,
    this.tripType = TripType.general,
  });

  final String id;
  final String corridorId;
  final DateTime departureTime;
  final int pricePerSeat;
  final int seatsAvailable;
  final int seatsTotal;
  final double driverRatingAvg;
  final String? driverName;
  final Gender? driverGender;
  final TripVehicle? vehicle;
  final TripType tripType;

  /// Warn (not celebrate) when only the last seat remains.
  bool get lastSeat => seatsAvailable == 1;

  factory TripSummary.fromJson(Map<String, dynamic> json) => TripSummary(
        id: json['id'] as String,
        corridorId: json['corridorId'] as String,
        departureTime: DateTime.parse(json['departureTime'] as String),
        pricePerSeat: (json['pricePerSeat'] as num).toInt(),
        seatsAvailable: (json['seatsAvailable'] as num).toInt(),
        seatsTotal: (json['seatsTotal'] as num).toInt(),
        driverRatingAvg: (json['driverRatingAvg'] as num?)?.toDouble() ?? 0,
        driverName: json['driverName'] as String?,
        driverGender: genderFromApi(json['driverGender'] as String?),
        vehicle: json['vehicle'] == null
            ? null
            : TripVehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
        tripType: tripTypeFrom(json['tripType'] as String?),
      );
}
