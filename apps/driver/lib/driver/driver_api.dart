import 'package:dio/dio.dart';
import 'package:shared/shared.dart';

import 'driver_models.dart';

/// Driver onboarding endpoints. Abstracted so the controller can be tested
/// against a fake (no real network / file system).
abstract interface class DriverApi {
  /// GET /driver/profile → the full profile, or null when the user is not yet a
  /// driver (the backend answers 404 in that case).
  Future<DriverProfile?> getProfile();

  /// POST /driver/profile → become a driver (status PENDING).
  Future<DriverProfile> createProfile();

  /// POST /driver/vehicle → add/replace the driver's single vehicle.
  Future<Vehicle> saveVehicle({
    required String make,
    required String model,
    required String plate,
    required String color,
    required int seats,
  });

  /// POST /driver/documents (multipart) → upload one verification document.
  Future<DriverDocument> uploadDocument({
    required DocType type,
    required String filePath,
  });
}

class DioDriverApi implements DriverApi {
  DioDriverApi(this._dio);

  final Dio _dio;

  @override
  Future<DriverProfile?> getProfile() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/driver/profile');
      return DriverProfile.fromJson(res.data!);
    } on DioException catch (e) {
      // 404 here means "not registered as a driver yet", not a real error.
      if (e.response?.statusCode == 404) return null;
      throw mapDioError(e);
    }
  }

  @override
  Future<DriverProfile> createProfile() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/driver/profile');
      return DriverProfile.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<Vehicle> saveVehicle({
    required String make,
    required String model,
    required String plate,
    required String color,
    required int seats,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/driver/vehicle',
        data: {
          'make': make,
          'model': model,
          'plate': plate,
          'color': color,
          'seats': seats,
        },
      );
      return Vehicle.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<DriverDocument> uploadDocument({
    required DocType type,
    required String filePath,
  }) async {
    try {
      final form = FormData.fromMap({
        'type': type.api,
        'file': await MultipartFile.fromFile(filePath),
      });
      final res =
          await _dio.post<Map<String, dynamic>>('/driver/documents', data: form);
      return DriverDocument.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
