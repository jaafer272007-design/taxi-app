import 'package:dio/dio.dart';
import 'package:shared/shared.dart';

import 'pool_models.dart';

/// The driver's half of Phase 2: browse the board, claim, propose a raise.
abstract interface class PoolApi {
  /// GET /pools/board — pools this driver's vehicle can actually take.
  Future<List<BoardPool>> board();

  /// POST /pools/:id/claim. Returns the id of the trip it became.
  ///
  /// Throws an [ApiException] carrying the server's `code` on refusal —
  /// `POOL_ALREADY_CLAIMED` and the rest. The caller branches on the code, not
  /// on the Arabic.
  Future<String> claim(String poolId);

  /// GET /pools/mine/:tripId — the pool behind a claimed trip, or null when the
  /// trip was posted by the driver and has none.
  Future<DriverPool?> forTrip(String tripId);

  /// POST /pools/:id/raise.
  Future<void> proposeRaise(String poolId, int newPricePerSeat);
}

class DioPoolApi implements PoolApi {
  DioPoolApi(this._dio);

  final Dio _dio;

  @override
  Future<List<BoardPool>> board() async {
    try {
      final res = await _dio.get<List<dynamic>>('/pools/board');
      return (res.data ?? const [])
          .map((e) => BoardPool.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<String> claim(String poolId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/pools/$poolId/claim');
      final trip = res.data?['trip'] as Map<String, dynamic>?;
      return trip?['id'] as String? ?? '';
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<DriverPool?> forTrip(String tripId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/pools/mine/$tripId');
      final data = res.data;
      // A driver-posted trip has no pool. The endpoint answers `null`, which
      // Dio surfaces as an empty body — both mean "not a pooled trip".
      if (data == null || data.isEmpty) return null;
      return DriverPool.fromJson(data);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> proposeRaise(String poolId, int newPricePerSeat) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/pools/$poolId/raise',
        data: {'newPricePerSeat': newPricePerSeat},
      );
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
