import 'package:dio/dio.dart';

import 'trip_models.dart';
import 'package:shared/shared.dart';

/// Corridor + trip-search endpoints. Abstracted so the controller can be tested
/// against a fake.
abstract interface class TripApi {
  Future<List<Corridor>> getCorridors();
  Future<List<TripSummary>> searchTrips({
    String? corridorId,
    DateTime? date,
    DateTime? fromTime,
    DateTime? toTime,
    TripType? tripType,
    Gender? driverGender,
  });

  /// Register that this rider wants a corridor nobody is serving yet.
  ///
  /// Returns nothing: the server's answer is the same either way — a duplicate
  /// tap is idempotent success, not an error — so there is nothing for the
  /// caller to branch on. Anything that fails throws, and only that is a
  /// failure worth showing.
  Future<void> requestRoute({required String corridorId, DateTime? requestedFor});
}

class DioTripApi implements TripApi {
  DioTripApi(this._dio);

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
  Future<List<TripSummary>> searchTrips({
    String? corridorId,
    DateTime? date,
    DateTime? fromTime,
    DateTime? toTime,
    TripType? tripType,
    Gender? driverGender,
  }) async {
    try {
      final query = <String, dynamic>{
        if (corridorId != null) 'corridorId': corridorId,
        if (date != null) 'date': _dateOnly(date),
        if (fromTime != null) 'fromTime': fromTime.toUtc().toIso8601String(),
        if (toTime != null) 'toTime': toTime.toUtc().toIso8601String(),
        if (tripType != null) 'tripType': tripType.apiValue,
        if (driverGender != null) 'driverGender': driverGender.apiValue,
      };
      final res = await _dio.get<List<dynamic>>(
        '/trips/search',
        queryParameters: query,
      );
      return (res.data ?? const [])
          .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> requestRoute({
    required String corridorId,
    DateTime? requestedFor,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/route-requests',
        data: <String, dynamic>{
          'corridorId': corridorId,
          if (requestedFor != null)
            'requestedFor': requestedFor.toUtc().toIso8601String(),
        },
      );
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// YYYY-MM-DD in the calendar the user picked (backend reads it as the
  /// Asia/Baghdad day).
  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
