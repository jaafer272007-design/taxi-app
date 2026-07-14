import 'package:dio/dio.dart';

import 'booking_models.dart';
import 'package:shared/shared.dart';

/// Rider-facing booking endpoints. Abstracted so the controller can be tested
/// against a fake.
abstract interface class BookingApi {
  /// POST /bookings → the created CONFIRMED booking. Throws [ApiException]
  /// (mapped) on 4xx — notably 409 when the seat was taken in the meantime.
  Future<Booking> create({
    required String tripId,
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required int seatCount,
  });

  /// GET /bookings/mine → the rider's bookings, newest first, each with its trip
  /// and an `upcoming` flag.
  Future<List<Booking>> listMine();

  /// POST /bookings/:id/cancel → the cancelled booking. Throws [ApiException]
  /// (409) when past the free-cancel cutoff.
  Future<Booking> cancel(String bookingId);
}

class DioBookingApi implements BookingApi {
  DioBookingApi(this._dio);

  final Dio _dio;

  @override
  Future<Booking> create({
    required String tripId,
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required int seatCount,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/bookings',
        data: {
          'tripId': tripId,
          'pickup': pickup.toJson(),
          'dropoff': dropoff.toJson(),
          'seatCount': seatCount,
        },
      );
      return Booking.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<List<Booking>> listMine() async {
    try {
      final res = await _dio.get<List<dynamic>>('/bookings/mine');
      return (res.data ?? const [])
          .map((e) => Booking.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<Booking> cancel(String bookingId) async {
    try {
      final res =
          await _dio.post<Map<String, dynamic>>('/bookings/$bookingId/cancel');
      return Booking.fromJson(res.data!);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
