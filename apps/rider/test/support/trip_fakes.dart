import 'package:rider/trip/trip_api.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:shared/shared.dart';

/// A scriptable fake of [TripApi] for tests — no real network.
class FakeTripApi implements TripApi {
  List<Corridor> corridors = const [];
  List<TripSummary> searchResults = const [];
  Object? corridorsError;
  Object? searchError;
  int getCorridorsCalls = 0;
  int searchCalls = 0;

  // Last search arguments (for asserting the filter → query mapping).
  String? lastCorridorId;
  TripType? lastTripType;
  Gender? lastDriverGender;

  @override
  Future<List<Corridor>> getCorridors() async {
    getCorridorsCalls++;
    if (corridorsError != null) throw corridorsError!;
    return corridors;
  }

  @override
  Future<List<TripSummary>> searchTrips({
    String? corridorId,
    DateTime? date,
    DateTime? fromTime,
    DateTime? toTime,
    TripType? tripType,
    Gender? driverGender,
  }) async {
    searchCalls++;
    lastCorridorId = corridorId;
    lastTripType = tripType;
    lastDriverGender = driverGender;
    if (searchError != null) throw searchError!;
    return searchResults;
  }
}

// ── fixtures ───────────────────────────────────────────────────────────────

const najafKarbala =
    Corridor(id: 'c1', originCity: 'Najaf', destCity: 'Karbala', pricePerSeat: 6000);
const karbalaNajaf =
    Corridor(id: 'c2', originCity: 'Karbala', destCity: 'Najaf', pricePerSeat: 6000);

/// A trip fixture. [hourUtc]/[minute] are UTC; +3h gives the Baghdad clock the
/// UI shows (e.g. hourUtc 4 → "07:00"), deterministic across machines.
TripSummary tripFixture({
  String id = 't1',
  int hourUtc = 4,
  int minute = 30,
  int price = 6000,
  int seatsAvailable = 3,
  int seatsTotal = 4,
  String? driverName = 'علي حسن',
  double rating = 4.5,
  TripVehicle? vehicle,
  TripType tripType = TripType.general,
  Gender? driverGender,
}) {
  return TripSummary(
    id: id,
    corridorId: 'c1',
    departureTime: DateTime.utc(2026, 7, 20, hourUtc, minute),
    pricePerSeat: price,
    seatsAvailable: seatsAvailable,
    seatsTotal: seatsTotal,
    driverRatingAvg: rating,
    driverName: driverName,
    driverGender: driverGender,
    vehicle: vehicle ??
        const TripVehicle(make: 'Toyota', model: 'Corolla', color: 'أبيض', seats: 4),
    tripType: tripType,
  );
}
