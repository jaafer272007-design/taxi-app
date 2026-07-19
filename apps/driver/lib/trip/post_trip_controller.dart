import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'driver_trip_api.dart';
import 'driver_trip_models.dart';

/// Departure mode for a new trip.
enum DepartMode { now, scheduled }

enum CorridorsLoad { loading, error, ready }

/// Drives the post-a-trip form: corridor selection, departure mode (now vs
/// scheduled), seat count (capped at the vehicle's seats), and submitting.
class PostTripController extends ChangeNotifier {
  PostTripController({required DriverTripApi api, required int maxSeats})
      : _api = api,
        _maxSeats = maxSeats < 1 ? 1 : maxSeats;

  final DriverTripApi _api;
  final int _maxSeats;

  CorridorsLoad _corridorsLoad = CorridorsLoad.loading;
  List<Corridor> _corridors = const []; // active only
  String? _origin;
  String? _dest;
  String? _corridorsError;

  DepartMode _mode = DepartMode.now;
  DateTime? _scheduledAt;
  int _seatCount = 1;
  TripType _tripType = TripType.general;

  bool _submitting = false;
  String? _error;
  DriverTrip? _posted;

  CorridorsLoad get corridorsLoad => _corridorsLoad;
  List<Corridor> get corridors => _corridors;
  String? get origin => _origin;
  String? get dest => _dest;
  String? get corridorsError => _corridorsError;
  DepartMode get mode => _mode;
  DateTime? get scheduledAt => _scheduledAt;
  int get seatCount => _seatCount;
  TripType get tripType => _tripType;
  int get maxSeats => _maxSeats;
  bool get submitting => _submitting;
  String? get error => _error;
  DriverTrip? get posted => _posted;

  /// The active corridor serving the picked (origin, dest), or null — the driver
  /// can only post once the admin has created a corridor for this pair.
  Corridor? get matchedCorridor {
    final o = _origin;
    final d = _dest;
    if (o == null || d == null) return null;
    for (final c in _corridors) {
      if (c.originCity == o && c.destCity == d) return c;
    }
    return null;
  }

  /// Both cities chosen and distinct, but no active corridor serves them yet.
  bool get noCorridorForPair =>
      _origin != null &&
      _dest != null &&
      _origin != _dest &&
      matchedCorridor == null;

  /// Read-only, system-set price for the matched corridor (per seat, IQD).
  int get pricePerSeat => matchedCorridor?.pricePerSeat ?? 0;

  bool get canDecrement => _seatCount > 1;
  bool get canIncrement => _seatCount < _maxSeats;

  bool get canSubmit =>
      !_submitting &&
      matchedCorridor != null &&
      (_mode == DepartMode.now || _scheduledAt != null);

  /// Load active corridors once (idempotent); defaults the from/to cities to the
  /// first served corridor.
  Future<void> loadCorridors() async {
    if (_corridors.isNotEmpty) return;
    _corridorsLoad = CorridorsLoad.loading;
    _corridorsError = null;
    notifyListeners();
    try {
      final all = await _api.getCorridors();
      _corridors = all.where((c) => c.active).toList();
      if (_origin == null && _dest == null && _corridors.isNotEmpty) {
        _origin = _corridors.first.originCity;
        _dest = _corridors.first.destCity;
      }
      _corridorsLoad = CorridorsLoad.ready;
    } on ApiException catch (e) {
      _corridorsError = e.message;
      _corridorsLoad = CorridorsLoad.error;
    } catch (_) {
      _corridorsError = 'تعذّر تحميل المسارات. حاول مرة أخرى.';
      _corridorsLoad = CorridorsLoad.error;
    } finally {
      notifyListeners();
    }
  }

  void setOrigin(String city) {
    _origin = city;
    notifyListeners();
  }

  void setDest(String city) {
    _dest = city;
    notifyListeners();
  }

  /// Swap the from/to cities.
  void swapCities() {
    final o = _origin;
    _origin = _dest;
    _dest = o;
    notifyListeners();
  }

  void setMode(DepartMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void setTripType(TripType type) {
    if (_tripType == type) return;
    _tripType = type;
    notifyListeners();
  }

  void setScheduledAt(DateTime? at) {
    _scheduledAt = at;
    notifyListeners();
  }

  void setSeatCount(int value) {
    final clamped = value.clamp(1, _maxSeats).toInt();
    if (clamped == _seatCount) return;
    _seatCount = clamped;
    notifyListeners();
  }

  void incrementSeat() => setSeatCount(_seatCount + 1);
  void decrementSeat() => setSeatCount(_seatCount - 1);

  /// Submit the trip. Returns true on success ([posted] then set).
  Future<bool> submit() async {
    if (_submitting || !canSubmit) return false;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      _posted = await _api.postTrip(
        corridorId: matchedCorridor!.id,
        seatsTotal: _seatCount,
        departNow: _mode == DepartMode.now,
        departureTime: _mode == DepartMode.scheduled ? _scheduledAt : null,
        tripType: _tripType,
      );
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}
