import 'package:flutter/foundation.dart';

import 'booking_api.dart';
import 'booking_models.dart';
import 'package:shared/shared.dart';

enum MyBookingsStatus { loading, error, loaded }

/// Loads and manages the rider's own bookings (GET /bookings/mine), grouped into
/// upcoming vs past, and drives cancellation.
class MyBookingsController extends ChangeNotifier {
  MyBookingsController({required BookingApi api}) : _api = api;

  final BookingApi _api;

  MyBookingsStatus _status = MyBookingsStatus.loading;
  List<Booking> _bookings = const [];
  String? _error;
  bool _hasLoaded = false;
  final Set<String> _cancelling = {};

  MyBookingsStatus get status => _status;
  String? get error => _error;

  /// True once a load attempt has finished (so a screen can avoid re-loading a
  /// controller that was pre-populated, e.g. in tests).
  bool get hasLoaded => _hasLoaded;

  /// Future-departure bookings (server-flagged), newest first.
  List<Booking> get upcoming =>
      _bookings.where((b) => b.upcoming ?? false).toList();

  /// Past bookings, newest first.
  List<Booking> get past =>
      _bookings.where((b) => !(b.upcoming ?? false)).toList();

  bool get isEmpty => _bookings.isEmpty;

  bool isCancelling(String id) => _cancelling.contains(id);

  /// A booking can be cancelled by the rider only while upcoming and CONFIRMED
  /// (the backend still enforces the 15-min cutoff).
  bool canCancel(Booking b) =>
      (b.upcoming ?? false) && b.status == BookingStatus.confirmed;

  Future<void> load() async {
    _status = MyBookingsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _bookings = await _api.listMine();
      _status = MyBookingsStatus.loaded;
    } on ApiException catch (e) {
      _error = e.message;
      _status = MyBookingsStatus.error;
    } catch (_) {
      _error = 'تعذّر تحميل حجوزاتك. حاول مرة أخرى.';
      _status = MyBookingsStatus.error;
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Cancel a booking. Returns null on success, else an Arabic message (e.g.
  /// past the cutoff) for the caller to surface. Guards double-cancel.
  Future<String?> cancel(String bookingId) async {
    if (_cancelling.contains(bookingId)) return null;
    _cancelling.add(bookingId);
    notifyListeners();
    try {
      final updated = await _api.cancel(bookingId);
      _bookings = [
        for (final b in _bookings)
          if (b.id == bookingId) _withStatus(b, updated.status) else b,
      ];
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر إلغاء الحجز. حاول مرة أخرى.';
    } finally {
      _cancelling.remove(bookingId);
      notifyListeners();
    }
  }

  Booking _withStatus(Booking b, BookingStatus status) => Booking(
        id: b.id,
        seatCount: b.seatCount,
        fare: b.fare,
        status: status,
        pickupLabel: b.pickupLabel,
        dropoffLabel: b.dropoffLabel,
        trip: b.trip,
        upcoming: b.upcoming,
      );
}
