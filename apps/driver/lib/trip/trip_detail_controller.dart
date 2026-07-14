import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'driver_trip_api.dart';
import 'driver_trip_models.dart';

enum TripDetailStatus { loading, error, loaded }

/// The completion summary shown once a trip is settled: how many seats actually
/// rode and how much cash was collected (sum over COMPLETED bookings).
class TripCompletionSummary {
  const TripCompletionSummary({
    required this.ridersCount,
    required this.seatsRidden,
    required this.cashCollected,
  });

  final int ridersCount;
  final int seatsRidden;
  final int cashCollected;
}

/// Drives one trip's detail screen: its bookings (GET /trips/:id/bookings) and
/// every lifecycle action the OWNING driver can take.
///
/// Actions return a nullable Arabic error string (null = success) so the screen
/// can surface a snackbar without the business logic reaching into the widget.
/// Wrong-state 409s from the backend flow straight through as their Arabic text.
class TripDetailController extends ChangeNotifier {
  TripDetailController({
    required DriverTripApi api,
    required DriverTrip trip,
    this.corridor,
  })  : _api = api,
        _trip = trip;

  final DriverTripApi _api;
  final Corridor? corridor;

  DriverTrip _trip;
  List<TripBooking> _bookings = const [];
  TripDetailStatus _loadStatus = TripDetailStatus.loading;
  String? _error;
  bool _hasLoaded = false;

  bool _tripActionInFlight = false;
  final Set<String> _bookingActionInFlight = {};
  final Set<String> _ratedRiderIds = {};
  TripCompletionSummary? _summary;

  /// True once any mutation happened, so the caller can refresh the trips list.
  bool changed = false;

  DriverTrip get trip => _trip;
  TripStatus get status => _trip.status;
  List<TripBooking> get bookings => _bookings;
  TripDetailStatus get loadStatus => _loadStatus;
  String? get error => _error;
  bool get isEmpty => _bookings.isEmpty;
  bool get hasLoaded => _hasLoaded;
  bool get tripActionInFlight => _tripActionInFlight;
  TripCompletionSummary? get summary => _summary;

  bool bookingActionInFlight(String bookingId) =>
      _bookingActionInFlight.contains(bookingId);
  bool isRated(String riderId) => _ratedRiderIds.contains(riderId);

  // ── UI gates (mirror the backend state machine) ───────────────────────────
  bool get canStart =>
      _trip.status == TripStatus.open || _trip.status == TripStatus.locked;
  bool get canCancel => canStart;
  bool get isEnRoute => _trip.status == TripStatus.enRoute;
  bool get isDone =>
      _trip.status == TripStatus.completed || _trip.status == TripStatus.settled;

  /// A booking can be marked onboard / no-show only while EN_ROUTE and still
  /// CONFIRMED (matches the backend guard).
  bool canTransition(TripBooking b) =>
      isEnRoute && b.status == BookingStatus.confirmed;

  /// Riders who rode (COMPLETED booking), deduped by riderId — the rate targets.
  List<TripBooking> get riddenRiders {
    final seen = <String>{};
    final out = <TripBooking>[];
    for (final b in _bookings) {
      if (b.status == BookingStatus.completed && seen.add(b.riderId)) {
        out.add(b);
      }
    }
    return out;
  }

  Future<void> load() async {
    _loadStatus = TripDetailStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _bookings = await _api.tripBookings(_trip.id);
      _loadStatus = TripDetailStatus.loaded;
    } on ApiException catch (e) {
      _error = e.message;
      _loadStatus = TripDetailStatus.error;
    } catch (_) {
      _error = 'تعذّر تحميل الحجوزات. حاول مرة أخرى.';
      _loadStatus = TripDetailStatus.error;
    }
    _hasLoaded = true;
    notifyListeners();
  }

  Future<String?> start() =>
      _simpleTripAction(_api.startTrip, TripStatus.enRoute,
          fallback: 'تعذّر بدء الرحلة. حاول مرة أخرى.');

  Future<String?> cancel() =>
      _simpleTripAction(_api.cancelTrip, TripStatus.cancelled,
          fallback: 'تعذّر إلغاء الرحلة. حاول مرة أخرى.');

  Future<String?> _simpleTripAction(
    Future<void> Function(String) call,
    TripStatus next, {
    required String fallback,
  }) async {
    if (_tripActionInFlight) return null;
    _tripActionInFlight = true;
    notifyListeners();
    try {
      await call(_trip.id);
      _trip = _trip.copyWith(status: next);
      changed = true;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return fallback;
    } finally {
      _tripActionInFlight = false;
      notifyListeners();
    }
  }

  /// Complete the trip, then refetch bookings so the summary and rate targets
  /// reflect the settled (COMPLETED) statuses.
  Future<String?> complete() async {
    if (_tripActionInFlight) return null;
    _tripActionInFlight = true;
    notifyListeners();
    try {
      await _api.completeTrip(_trip.id);
      _trip = _trip.copyWith(status: TripStatus.settled);
      changed = true;
      try {
        _bookings = await _api.tripBookings(_trip.id);
      } catch (_) {
        // Non-fatal: the trip IS settled; keep the pre-complete bookings if the
        // refetch fails so the summary is a best-effort estimate.
      }
      _summary = _buildSummary();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر إنهاء الرحلة. حاول مرة أخرى.';
    } finally {
      _tripActionInFlight = false;
      notifyListeners();
    }
  }

  TripCompletionSummary _buildSummary() {
    final rode =
        _bookings.where((b) => b.status == BookingStatus.completed).toList();
    return TripCompletionSummary(
      ridersCount: rode.length,
      seatsRidden: rode.fold<int>(0, (s, b) => s + b.seatCount),
      cashCollected: rode.fold<int>(0, (s, b) => s + b.fare),
    );
  }

  Future<String?> onboard(String bookingId) => _bookingTransition(
      bookingId, () => _api.onboard(bookingId), BookingStatus.onboard);

  Future<String?> noShow(String bookingId) => _bookingTransition(
      bookingId, () => _api.noShow(bookingId), BookingStatus.noShow);

  Future<String?> _bookingTransition(
    String bookingId,
    Future<void> Function() call,
    BookingStatus next,
  ) async {
    if (_bookingActionInFlight.contains(bookingId)) return null;
    _bookingActionInFlight.add(bookingId);
    notifyListeners();
    try {
      await call();
      _bookings = [
        for (final b in _bookings)
          if (b.id == bookingId) b.copyWith(status: next) else b,
      ];
      changed = true;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر تحديث حالة الراكب. حاول مرة أخرى.';
    } finally {
      _bookingActionInFlight.remove(bookingId);
      notifyListeners();
    }
  }

  /// Rate a rider who rode. One per rider per trip. A server 409 (already rated,
  /// e.g. in a previous session) is idempotent from the UI's view: mark the
  /// rider rated and report success so the sheet closes cleanly instead of
  /// flashing an error for something that is effectively already done.
  Future<String?> rateRider({
    required String riderId,
    required int score,
    String? comment,
  }) async {
    try {
      await _api.rateRider(
        tripId: _trip.id,
        toUserId: riderId,
        score: score,
        comment: comment,
      );
      _ratedRiderIds.add(riderId);
      changed = true;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _ratedRiderIds.add(riderId);
        notifyListeners();
        return null;
      }
      return e.message;
    } catch (_) {
      return 'تعذّر إرسال التقييم. حاول مرة أخرى.';
    }
  }
}
