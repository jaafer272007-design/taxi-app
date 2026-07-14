import 'package:dio/dio.dart';
import 'package:shared/shared.dart';

import 'driver_trip_models.dart';

/// Corridor + trip-posting endpoints for the driver app.
abstract interface class DriverTripApi {
  Future<List<Corridor>> getCorridors();

  /// POST /trips. Provide EITHER [departNow] = true OR a future [departureTime]
  /// — never both, never neither (the backend rejects both cases).
  Future<DriverTrip> postTrip({
    required String corridorId,
    required int seatsTotal,
    bool departNow = false,
    DateTime? departureTime,
  });

  Future<List<DriverTrip>> myTrips();

  /// GET /trips/:id/bookings — the bookings on the driver's own trip, each with
  /// the rider's resolved name, seats, pickup/dropoff and status.
  Future<List<TripBooking>> tripBookings(String tripId);

  /// POST /trips/:id/start — OPEN|LOCKED → EN_ROUTE.
  Future<void> startTrip(String tripId);

  /// POST /trips/:id/complete — EN_ROUTE → SETTLED (settles riders, records cash).
  Future<void> completeTrip(String tripId);

  /// POST /trips/:id/cancel — OPEN|LOCKED → CANCELLED (before departure).
  Future<void> cancelTrip(String tripId);

  /// POST /bookings/:id/onboard — CONFIRMED → ONBOARD (trip must be EN_ROUTE).
  Future<void> onboard(String bookingId);

  /// POST /bookings/:id/no-show — CONFIRMED → NO_SHOW (trip must be EN_ROUTE).
  Future<void> noShow(String bookingId);

  /// GET /driver/earnings?range=today|all — cash total + per-trip records.
  Future<DriverEarnings> earnings({required String range});

  /// POST /ratings — rate a rider who rode this trip (score 1..5, optional note).
  Future<void> rateRider({
    required String tripId,
    required String toUserId,
    required int score,
    String? comment,
  });
}

class DioDriverTripApi implements DriverTripApi {
  DioDriverTripApi(this._dio);

  final Dio _dio;

  @override
  Future<List<Corridor>> getCorridors() async {
    try {
      final res = await _dio.get<List<dynamic>>('/corridors');
      return (res.data ?? const [])
          .map((e) => Corridor.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<DriverTrip> postTrip({
    required String corridorId,
    required int seatsTotal,
    bool departNow = false,
    DateTime? departureTime,
  }) async {
    try {
      // Send only the fields the backend expects (forbidNonWhitelisted); exactly
      // one of departNow/departureTime.
      final data = <String, dynamic>{
        'corridorId': corridorId,
        'seatsTotal': seatsTotal,
      };
      if (departNow) {
        data['departNow'] = true;
      } else if (departureTime != null) {
        data['departureTime'] = departureTime.toUtc().toIso8601String();
      }
      final res = await _dio.post<Map<String, dynamic>>('/trips', data: data);
      return DriverTrip.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<List<DriverTrip>> myTrips() async {
    try {
      final res = await _dio.get<List<dynamic>>('/trips/mine');
      return (res.data ?? const [])
          .map((e) => DriverTrip.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<List<TripBooking>> tripBookings(String tripId) async {
    try {
      final res = await _dio.get<List<dynamic>>('/trips/$tripId/bookings');
      return (res.data ?? const [])
          .map((e) => TripBooking.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> startTrip(String tripId) => _post('/trips/$tripId/start');

  @override
  Future<void> completeTrip(String tripId) => _post('/trips/$tripId/complete');

  @override
  Future<void> cancelTrip(String tripId) => _post('/trips/$tripId/cancel');

  @override
  Future<void> onboard(String bookingId) => _post('/bookings/$bookingId/onboard');

  @override
  Future<void> noShow(String bookingId) => _post('/bookings/$bookingId/no-show');

  @override
  Future<DriverEarnings> earnings({required String range}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/driver/earnings',
        queryParameters: {'range': range},
      );
      return DriverEarnings.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> rateRider({
    required String tripId,
    required String toUserId,
    required int score,
    String? comment,
  }) async {
    try {
      // Send only whitelisted fields; omit an empty comment entirely.
      final data = <String, dynamic>{
        'tripId': tripId,
        'toUserId': toUserId,
        'score': score,
      };
      if (comment != null && comment.trim().isNotEmpty) {
        data['comment'] = comment.trim();
      }
      await _dio.post<Map<String, dynamic>>('/ratings', data: data);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// A POST whose response body we don't need (lifecycle transitions return the
  /// updated row, but the client refetches rather than trusting the shape).
  Future<void> _post(String path) async {
    try {
      await _dio.post<dynamic>(path);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
