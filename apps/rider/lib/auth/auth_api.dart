import 'package:dio/dio.dart';

import '../core/api_exception.dart';
import '../core/token_store.dart';
import 'auth_user.dart';

/// The auth endpoints the app talks to. Abstracted so the AuthController can be
/// tested against a fake (no real network).
abstract interface class AuthApi {
  Future<void> requestOtp(String phone);
  Future<AuthSession> verifyOtp(String phone, String code);
  Future<AuthUser> me();
  Future<AuthUser> updateName(String name);
}

/// Dio-backed implementation. A JWT interceptor attaches the stored token to
/// every request (harmless on the public OTP endpoints, required for /auth/me).
class DioAuthApi implements AuthApi {
  DioAuthApi({
    required String baseUrl,
    required TokenStore tokenStore,
    Dio? dio,
  })  : _tokenStore = tokenStore,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              contentType: Headers.jsonContentType,
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokenStore;

  @override
  Future<void> requestOtp(String phone) async {
    try {
      await _dio.post<dynamic>('/auth/request-otp', data: {'phone': phone});
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthSession> verifyOtp(String phone, String code) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/verify-otp',
        data: {'phone': phone, 'code': code},
      );
      final data = res.data!;
      return AuthSession(
        accessToken: data['accessToken'] as String,
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthUser> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      return AuthUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthUser> updateName(String name) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/auth/me',
        data: {'name': name},
      );
      return AuthUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static const _networkTypes = {
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
  };

  ApiException _map(DioException e) {
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
      429 => 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
      401 => 'رمز التحقق غير صحيح أو منتهي الصلاحية.',
      _ => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };
  }
}
