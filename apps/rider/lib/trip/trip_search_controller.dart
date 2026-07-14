import 'package:flutter/material.dart';

import 'trip_api.dart';
import 'trip_models.dart';
import 'package:shared/shared.dart';

enum TripSearchStatus { initial, loading, results, empty, error }

/// Holds the search form (corridor, date, time window) and the results/loading/
/// empty/error state for browsing driver-posted trips.
class TripSearchController extends ChangeNotifier {
  TripSearchController({required TripApi api}) : _api = api;

  final TripApi _api;

  // ── corridors ──
  List<Corridor> _corridors = const [];
  Corridor? _corridor;
  bool _corridorsLoading = false;
  String? _corridorsError;

  // ── form ──
  /// `null` = today.
  DateTime? _date;
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;

  // ── results ──
  List<TripSummary> _results = const [];
  TripSearchStatus _status = TripSearchStatus.initial;
  String? _error;

  List<Corridor> get corridors => _corridors;
  Corridor? get corridor => _corridor;
  bool get corridorsLoading => _corridorsLoading;
  String? get corridorsError => _corridorsError;

  DateTime? get date => _date;
  TimeOfDay? get fromTime => _fromTime;
  TimeOfDay? get toTime => _toTime;
  bool get hasTimeWindow => _fromTime != null && _toTime != null;

  List<TripSummary> get results => _results;
  TripSearchStatus get status => _status;
  String? get error => _error;

  /// Load corridors once (idempotent). Default-selects the first corridor.
  Future<void> ensureCorridorsLoaded() async {
    if (_corridors.isNotEmpty || _corridorsLoading) return;
    _corridorsLoading = true;
    _corridorsError = null;
    notifyListeners();
    try {
      _corridors = await _api.getCorridors();
      _corridor ??= _corridors.isEmpty ? null : _corridors.first;
    } on ApiException catch (e) {
      _corridorsError = e.message;
    } catch (_) {
      _corridorsError = 'تعذّر تحميل المسارات. حاول مرة أخرى.';
    } finally {
      _corridorsLoading = false;
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

  void setDate(DateTime? date) {
    _date = date;
    notifyListeners();
  }

  void setTimeWindow(TimeOfDay? from, TimeOfDay? to) {
    _fromTime = from;
    _toTime = to;
    notifyListeners();
  }

  void clearTimeWindow() {
    _fromTime = null;
    _toTime = null;
    notifyListeners();
  }

  /// Run the search for the current form. Results are sorted by departure time.
  Future<void> search() async {
    final corridor = _corridor;
    if (corridor == null) return;

    _status = TripSearchStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final day = _date ?? _today();
      DateTime? from;
      DateTime? to;
      if (_fromTime != null) {
        from = DateTime(day.year, day.month, day.day, _fromTime!.hour, _fromTime!.minute);
      }
      if (_toTime != null) {
        to = DateTime(day.year, day.month, day.day, _toTime!.hour, _toTime!.minute);
      }

      // Copy before sorting — never mutate the list the API handed us (it may
      // be unmodifiable).
      final results = List<TripSummary>.of(
        await _api.searchTrips(
          corridorId: corridor.id,
          date: day,
          fromTime: from,
          toTime: to,
        ),
      );
      results.sort((a, b) => a.departureTime.compareTo(b.departureTime));

      _results = results;
      _status =
          results.isEmpty ? TripSearchStatus.empty : TripSearchStatus.results;
    } on ApiException catch (e) {
      _error = e.message;
      _status = TripSearchStatus.error;
    } catch (_) {
      _error = 'حدث خطأ. حاول مرة أخرى.';
      _status = TripSearchStatus.error;
    } finally {
      notifyListeners();
    }
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
