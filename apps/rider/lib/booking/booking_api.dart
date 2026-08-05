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

  /// GET /trips/:id/contacts → the driver's number for a trip this rider has
  /// booked.
  ///
  /// The ONLY endpoint in the app that returns a phone number, so the rule
  /// "not before a booking exists" has one place to live on the server. A 403
  /// is a normal answer (no live booking on that trip) and the caller renders
  /// no contact row — it is not an error to show the rider.
  Future<TripContact?> driverContact(String tripId);

  /// POST /ratings → rate the driver of a completed trip. One per
  /// (trip, from, to); the server answers 409 on a repeat.
  Future<void> rateDriver({
    required String tripId,
    required String toUserId,
    required int score,
    String? comment,
  });
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

  @override
  Future<void> rateDriver({
    required String tripId,
    required String toUserId,
    required int score,
    String? comment,
  }) async {
    try {
      // Send only whitelisted fields; omit an empty comment entirely rather
      // than posting "" — the same shape the driver app sends.
      final data = <String, dynamic>{
        'tripId': tripId,
        'toUserId': toUserId,
        'score': score,
      };
      if (comment != null && comment.trim().isNotEmpty) {
        data['comment'] = comment.trim();
      }
      await _dio.post<dynamic>('/ratings', data: data);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<TripContact?> driverContact(String tripId) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/trips/$tripId/contacts');
      final list = (res.data?['contacts'] as List<dynamic>?) ?? const [];
      if (list.isEmpty) return null;
      // A rider is entitled to exactly one contact — their driver.
      return TripContact.fromJson(list.first as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
