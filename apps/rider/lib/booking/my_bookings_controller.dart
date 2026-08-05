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

  /// Driver numbers, keyed by bookingId. Only ever populated for bookings the
  /// server was willing to answer for — see [_loadContacts].
  Map<String, TripContact> _contactsByBooking = const {};
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

  /// The driver's contact for a booking, or null when the rider is not entitled
  /// to it (cancelled booking) or the lookup did not resolve. Null means "draw
  /// no contact row" — never "draw an empty one".
  TripContact? contactFor(String bookingId) => _contactsByBooking[bookingId];

  /// A booking can be cancelled by the rider only while upcoming and CONFIRMED
  /// (the backend still enforces the 15-min cutoff).
  bool canCancel(Booking b) =>
      (b.upcoming ?? false) && b.status == BookingStatus.confirmed;

  /// A BACKGROUND refresh: no spinner, and **no clearing on failure**.
  ///
  /// This is what the poll and the pull-to-refresh call. A rider watching for
  /// their driver to start the trip must not have the list replaced by an
  /// error the moment a request drops on a bad connection.
  Future<void> refreshSilently() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _status = MyBookingsStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      _bookings = await _api.listMine();
      _status = MyBookingsStatus.loaded;
      _error = null;
      await _loadContacts();
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = MyBookingsStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'تعذّر تحميل حجوزاتك. حاول مرة أخرى.';
        _status = MyBookingsStatus.error;
      }
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Whether anything on this screen can still change on its own.
  ///
  /// An upcoming booking can be started, completed or cancelled by the driver.
  /// A history of finished trips cannot change at all, and polling it would be
  /// asking the server the same question forever.
  bool get hasLiveBookings => _bookings.any((b) =>
      (b.upcoming ?? false) &&
      b.status != BookingStatus.cancelled &&
      b.status != BookingStatus.completed);

  /// Resolve the driver's number for the bookings that could use one.
  ///
  /// Only [canContact] bookings are asked about: a past or cancelled booking
  /// would get a 403, and firing requests we expect to be refused would turn a
  /// long history into a burst of failures on every load.
  ///
  /// One request per trip is the cost of keeping the entitlement rule in a
  /// single server-side place instead of copying it into `/bookings/mine`. A
  /// rider has a handful of upcoming trips, and they run concurrently.
  /// Individual failures are swallowed: no number is a missing convenience,
  /// not a broken screen.
  Future<void> _loadContacts() async {
    final wanted = _bookings.where(canContact).toList();
    if (wanted.isEmpty) {
      _contactsByBooking = const {};
      return;
    }

    final resolved = <String, TripContact>{};
    await Future.wait(wanted.map((b) async {
      final tripId = b.trip?.id;
      if (tripId == null) return;
      try {
        final contact = await _api.driverContact(tripId);
        if (contact != null) resolved[b.id] = contact;
      } catch (_) {
        // 403 (not entitled), offline, anything: no row for this booking.
      }
    }));
    _contactsByBooking = resolved;
  }

  /// Whether it is worth asking the server for this booking's driver number.
  ///
  /// A mirror of the server's rule, not a second enforcement of it: the server
  /// is still the only thing that decides, and it refuses anything this misses.
  /// This exists purely so a rider with twenty cancelled bookings does not fire
  /// twenty requests destined for 403.
  static bool canContact(Booking b) =>
      b.trip != null &&
      (b.upcoming ?? false) &&
      b.status != BookingStatus.cancelled;

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
      // The number goes with the booking. The server would refuse it on the
      // next load anyway; dropping it now means the rider never sees a stale
      // "call your driver" on a seat they just gave up.
      _contactsByBooking = {..._contactsByBooking}..remove(bookingId);
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
        pickup: b.pickup,
        dropoff: b.dropoff,
        trip: b.trip,
        upcoming: b.upcoming,
      );
}
