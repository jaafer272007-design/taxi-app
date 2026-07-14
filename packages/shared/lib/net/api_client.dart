import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'token_store.dart';

/// Owns the shared [Dio] instance used by every API client: base URL, timeouts,
/// and a JWT interceptor that attaches the stored token to each request
/// (harmless on public endpoints, required for authenticated ones).
class ApiClient {
  ApiClient({required String baseUrl, required TokenStore tokenStore})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          contentType: Headers.jsonContentType,
        )) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStore.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
}

const _networkTypes = {
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
  DioExceptionType.connectionError,
};

/// Maps a [DioException] to a user-facing [ApiException] (always Arabic).
ApiException mapDioError(DioException e) {
  if (_networkTypes.contains(e.type) || e.response == null) {
    return const ApiException(
      'تعذّر الاتصال بالخادم. تحقّق من الإنترنت وحاول مرة أخرى.',
      isNetwork: true,
    );
  }
  final status = e.response!.statusCode;
  return ApiException(_serverMessage(e.response!.data, status),
      statusCode: status);
}

/// Prefer the backend's Arabic message; fall back by status code.
String _serverMessage(dynamic data, int? status) {
  if (data is Map) {
    final msg = data['message'];
    if (msg is String && msg.trim().isNotEmpty) return msg;
    if (msg is List && msg.isNotEmpty) return msg.first.toString();
  }
  return switch (status) {
    401 => 'انتهت الجلسة. سجّل الدخول من جديد.',
    403 => 'ليس لديك صلاحية لهذا الإجراء.',
    404 => 'غير موجود.',
    429 => 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
    _ => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
  };
}
