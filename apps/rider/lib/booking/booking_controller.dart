import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../trip/trip_models.dart';
import 'booking_api.dart';
import 'booking_error.dart';
import 'booking_models.dart';
import 'package:shared/shared.dart';

/// Drives the reserve-a-seat flow for one [trip]: seat count, pickup/dropoff
/// points, the live fare, and submitting the booking. Owns a single booking
/// attempt; the confirmation screen reads [result] on success.
class BookingController extends ChangeNotifier {
  BookingController({
    required BookingApi api,
    required this.trip,
    this.originCity,
    this.destCity,
  })  : _api = api,
        _pickup = cityCenter(originCity),
        _dropoff = cityCenter(destCity);

  final BookingApi _api;

  /// The trip being booked (carried over from search/details).
  final TripSummary trip;

  /// English city keys for the trip's endpoints, used for the field labels and
  /// the default coordinates. Null when unknown (falls back to generic labels).
  final String? originCity;
  final String? destCity;

  int _seatCount = 1;
  GeoPoint _pickup;
  GeoPoint _dropoff;
  bool _pickupSet = false;
  bool _dropoffSet = false;
  bool _submitting = false;
  BookingError? _error;
  Booking? _result;

  int get seatCount => _seatCount;
  GeoPoint get pickup => _pickup;
  GeoPoint get dropoff => _dropoff;

  /// Whether the rider has explicitly chosen each point on the map. Both are
  /// required before the booking can be submitted.
  bool get pickupSet => _pickupSet;
  bool get dropoffSet => _dropoffSet;
  bool get submitting => _submitting;
  BookingError? get error => _error;
  Booking? get result => _result;

  /// Cap seats at 4 per booking and never above what's available.
  int get maxSeats => math.min(4, trip.seatsAvailable);

  /// Live total = price per seat × seats.
  int get fare => trip.pricePerSeat * _seatCount;

  bool get canDecrement => _seatCount > 1;
  bool get canIncrement => _seatCount < maxSeats;

  /// Ready to submit: both points chosen on the map and no booking in flight.
  bool get canSubmit => !_submitting && _pickupSet && _dropoffSet;

  void setSeatCount(int value) {
    // `maxSeats` is >= 1 for any bookable trip; guard the upper bound anyway so
    // clamp() never sees upper < lower.
    final upper = maxSeats < 1 ? 1 : maxSeats;
    final clamped = value.clamp(1, upper).toInt();
    if (clamped == _seatCount) return;
    _seatCount = clamped;
    notifyListeners();
  }

  void incrementSeat() => setSeatCount(_seatCount + 1);
  void decrementSeat() => setSeatCount(_seatCount - 1);

  /// The rider picked the pickup point on the map (coords + label).
  void setPickupPoint(GeoPoint point) {
    _pickup = point;
    _pickupSet = true;
    if (_error?.kind == BookingErrorKind.invalid) _error = null;
    notifyListeners();
  }

  /// The rider picked the dropoff point on the map (coords + label).
  void setDropoffPoint(GeoPoint point) {
    _dropoff = point;
    _dropoffSet = true;
    if (_error?.kind == BookingErrorKind.invalid) _error = null;
    notifyListeners();
  }

  /// Submit the booking. Guards against double-submit (a second call while one
  /// is in flight is ignored). Returns true on success ([result] is then set).
  Future<bool> submit() async {
    if (_submitting) return false;
    if (!canSubmit) return false;

    _submitting = true;
    _error = null;
    notifyListeners();

    try {
      _result = await _api.create(
        tripId: trip.id,
        pickup: _pickup,
        dropoff: _dropoff,
        seatCount: _seatCount,
      );
      return true;
    } on ApiException catch (e) {
      _error = classifyBookingError(e);
      return false;
    } catch (_) {
      _error = const BookingError(
        BookingErrorKind.generic,
        'حدث خطأ غير متوقع. حاول مرة أخرى.',
      );
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Clear the current error (e.g. after the rider dismisses a banner).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
