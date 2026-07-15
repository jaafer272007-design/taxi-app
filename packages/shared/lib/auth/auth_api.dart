import 'package:dio/dio.dart';

import '../net/api_client.dart';
import 'auth_user.dart';

/// The auth endpoints the app talks to. Abstracted so the AuthController can be
/// tested against a fake (no real network).
abstract interface class AuthApi {
  Future<void> requestOtp(String phone);
  Future<AuthSession> verifyOtp(String phone, String code);
  Future<AuthUser> me();
  Future<AuthUser> updateName(String name);

  /// Partial profile update (`PATCH /auth/me`). Each provided field is written
  /// on its own; omitted fields are left untouched. Used by onboarding to set
  /// name + gender together (completing the profile).
  Future<AuthUser> updateProfile({String? name, Gender? gender});
}

/// Dio-backed implementation. Uses the shared [ApiClient] Dio (JWT interceptor
/// attaches the token automatically for /auth/me).
class DioAuthApi implements AuthApi {
  DioAuthApi(this._dio);

  final Dio _dio;

  @override
  Future<void> requestOtp(String phone) async {
    try {
      await _dio.post<dynamic>('/auth/request-otp', data: {'phone': phone});
    } on DioException catch (e) {
      throw mapDioError(e);
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
      throw mapDioError(e);
    }
  }

  @override
  Future<AuthUser> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      return AuthUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
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
      throw mapDioError(e);
    }
  }

  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/auth/me',
        data: {
          if (name != null) 'name': name,
          if (gender != null) 'gender': gender.apiValue,
        },
      );
      return AuthUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
