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
}
