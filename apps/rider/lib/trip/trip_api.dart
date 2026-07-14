import 'package:dio/dio.dart';

import '../core/api_client.dart';
import 'trip_models.dart';

/// Corridor + trip-search endpoints. Abstracted so the controller can be tested
/// against a fake.
abstract interface class TripApi {
  Future<List<Corridor>> getCorridors();
  Future<List<TripSummary>> searchTrips({
    String? corridorId,
    DateTime? date,
    DateTime? fromTime,
    DateTime? toTime,
  });
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
  }) async {
    try {
      final query = <String, dynamic>{
        if (corridorId != null) 'corridorId': corridorId,
        if (date != null) 'date': _dateOnly(date),
        if (fromTime != null) 'fromTime': fromTime.toUtc().toIso8601String(),
        if (toTime != null) 'toTime': toTime.toUtc().toIso8601String(),
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

  /// YYYY-MM-DD in the calendar the user picked (backend reads it as the
  /// Asia/Baghdad day).
  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
