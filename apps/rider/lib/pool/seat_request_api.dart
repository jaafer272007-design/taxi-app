import 'package:dio/dio.dart';
import 'package:shared/shared.dart';

import 'seat_request_models.dart';

/// Phase 2 rider endpoints. Behind an interface so the controller is testable
/// against a fake, like every other API in this app.
abstract interface class SeatRequestApi {
  Future<SeatRequest> create(SeatRequestDraft draft);
  Future<List<SeatRequest>> listMine();
  Future<void> cancel(String id);

  /// Answer a price raise. `accept: false` is a first-class action, not the
  /// absence of one — declining releases the rider immediately, free.
  Future<void> respondToRaise(String id, {required bool accept});
}

class DioSeatRequestApi implements SeatRequestApi {
  DioSeatRequestApi(this._dio);

  final Dio _dio;

  @override
  Future<SeatRequest> create(SeatRequestDraft draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/seat-requests',
        data: draft.toJson(),
      );
      return SeatRequest.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<List<SeatRequest>> listMine() async {
    try {
      final res = await _dio.get<List<dynamic>>('/seat-requests/mine');
      return (res.data ?? const [])
          .map((e) => SeatRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> cancel(String id) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/seat-requests/$id');
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> respondToRaise(String id, {required bool accept}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/seat-requests/$id/raise-response',
        data: {'accept': accept},
      );
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
