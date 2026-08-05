import 'package:dio/dio.dart';

// mapDioError lives beside the client, not beside ApiException.
import '../net/api_client.dart';
import 'app_notification.dart';

/// The notification centre's endpoints. Shared: rider and driver read the same
/// inbox, differing only in which events reach them.
abstract interface class NotificationApi {
  /// GET /notifications → the list AND the unread count, in one round trip.
  Future<NotificationFeed> list();

  /// POST /notifications/:id/read. Idempotent server-side.
  Future<void> markRead(String id);

  /// POST /notifications/read-all.
  Future<void> markAllRead();
}

class DioNotificationApi implements NotificationApi {
  DioNotificationApi(this._dio);

  final Dio _dio;

  @override
  Future<NotificationFeed> list() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/notifications');
      return NotificationFeed.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> markRead(String id) async {
    try {
      await _dio.post<dynamic>('/notifications/$id/read');
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> markAllRead() async {
    try {
      await _dio.post<dynamic>('/notifications/read-all');
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
