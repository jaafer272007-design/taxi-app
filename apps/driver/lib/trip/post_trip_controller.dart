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
  List<Corridor> _corridors = const [];
  Corridor? _corridor;
  String? _corridorsError;

  DepartMode _mode = DepartMode.now;
  DateTime? _scheduledAt;
  int _seatCount = 1;

  bool _submitting = false;
  String? _error;
  DriverTrip? _posted;

  CorridorsLoad get corridorsLoad => _corridorsLoad;
  List<Corridor> get corridors => _corridors;
  Corridor? get corridor => _corridor;
  String? get corridorsError => _corridorsError;
  DepartMode get mode => _mode;
  DateTime? get scheduledAt => _scheduledAt;
  int get seatCount => _seatCount;
  int get maxSeats => _maxSeats;
  bool get submitting => _submitting;
  String? get error => _error;
  DriverTrip? get posted => _posted;

  /// Read-only, system-set price for the selected corridor (per seat, IQD).
  int get pricePerSeat => _corridor?.pricePerSeat ?? 0;

  bool get canDecrement => _seatCount > 1;
  bool get canIncrement => _seatCount < _maxSeats;

  bool get canSubmit =>
      !_submitting &&
      _corridor != null &&
      (_mode == DepartMode.now || _scheduledAt != null);

  /// Load active corridors once (idempotent); default-selects the first.
  Future<void> loadCorridors() async {
    if (_corridors.isNotEmpty) return;
    _corridorsLoad = CorridorsLoad.loading;
    _corridorsError = null;
    notifyListeners();
    try {
      final all = await _api.getCorridors();
      _corridors = all.where((c) => c.active).toList();
      _corridor ??= _corridors.isEmpty ? null : _corridors.first;
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

  void selectCorridor(Corridor corridor) {
    _corridor = corridor;
    notifyListeners();
  }

  /// Swap to the reverse-direction corridor (Najaf→Karbala ⇆ Karbala→Najaf).
  void swapDirection() {
    final current = _corridor;
    if (current == null) return;
    for (final c in _corridors) {
      if (c.originCity == current.destCity && c.destCity == current.originCity) {
        _corridor = c;
        notifyListeners();
        return;
      }
    }
  }

  void setMode(DepartMode mode) {
    if (_mode == mode) return;
    _mode = mode;
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
        corridorId: _corridor!.id,
        seatsTotal: _seatCount,
        departNow: _mode == DepartMode.now,
        departureTime: _mode == DepartMode.scheduled ? _scheduledAt : null,
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
