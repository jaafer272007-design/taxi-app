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

  // ── corridors (loaded once; used to resolve a picked city pair → corridor) ──
  List<Corridor> _corridors = const [];
  bool _corridorsLoading = false;
  String? _corridorsError;

  // ── route (from/to cities, chosen from the canonical 18-city list) ──
  String? _origin;
  String? _dest;

  // ── form ──
  /// `null` = today.
  DateTime? _date;
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;

  // ── filters (optional; `null` = "الكل") ──
  TripType? _tripType;
  Gender? _driverGender;

  // ── results ──
  List<TripSummary> _results = const [];
  TripSearchStatus _status = TripSearchStatus.initial;
  String? _error;

  List<Corridor> get corridors => _corridors;
  bool get corridorsLoading => _corridorsLoading;
  String? get corridorsError => _corridorsError;

  /// Picked origin / destination city keys (stored English values).
  String? get origin => _origin;
  String? get dest => _dest;

  /// The corridor serving the picked (origin, dest), if the admin created one.
  /// `null` means this pair isn't served yet → search shows the empty state.
  Corridor? get matchedCorridor {
    final o = _origin;
    final d = _dest;
    if (o == null || d == null) return null;
    for (final c in _corridors) {
      if (c.originCity == o && c.destCity == d) return c;
    }
    return null;
  }

  /// Both endpoints chosen and distinct.
  bool get canSearch => _origin != null && _dest != null && _origin != _dest;

  DateTime? get date => _date;
  TimeOfDay? get fromTime => _fromTime;
  TimeOfDay? get toTime => _toTime;
  bool get hasTimeWindow => _fromTime != null && _toTime != null;

  /// Optional filters. `null` means "الكل" (no restriction).
  TripType? get tripType => _tripType;
  Gender? get driverGender => _driverGender;
  bool get hasActiveFilters => _tripType != null || _driverGender != null;

  List<TripSummary> get results => _results;
  TripSearchStatus get status => _status;
  String? get error => _error;

  /// Load corridors once (idempotent). Defaults the from/to cities to the first
  /// served corridor so the initial state is immediately searchable.
  Future<void> ensureCorridorsLoaded() async {
    if (_corridors.isNotEmpty || _corridorsLoading) return;
    _corridorsLoading = true;
    _corridorsError = null;
    notifyListeners();
    try {
      _corridors = await _api.getCorridors();
      if (_origin == null && _dest == null && _corridors.isNotEmpty) {
        _origin = _corridors.first.originCity;
        _dest = _corridors.first.destCity;
      }
    } on ApiException catch (e) {
      _corridorsError = e.message;
    } catch (_) {
      _corridorsError = 'تعذّر تحميل المسارات. حاول مرة أخرى.';
    } finally {
      _corridorsLoading = false;
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

  /// Filter by trip audience (`null` = all).
  void setTripType(TripType? type) {
    _tripType = type;
    notifyListeners();
  }

  /// Filter by the driver's gender (`null` = all). Female drivers are rare, so
  /// this often yields an empty list — a valid, handled result, not an error.
  void setDriverGender(Gender? gender) {
    _driverGender = gender;
    notifyListeners();
  }

  /// Drop both optional filters (the empty-state "إزالة الفلاتر" action). The
  /// caller re-runs [search] afterwards.
  void clearFilters() {
    _tripType = null;
    _driverGender = null;
    notifyListeners();
  }

  /// Run the search for the current form. Results are sorted by departure time.
  Future<void> search() async {
    if (!canSearch) return;
    final corridor = matchedCorridor;

    // No corridor for this city pair yet → a valid empty result (not an error,
    // not an API call). The empty view explains it clearly.
    if (corridor == null) {
      _results = const [];
      _error = null;
      _status = TripSearchStatus.empty;
      notifyListeners();
      return;
    }

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
          tripType: _tripType,
          driverGender: _driverGender,
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
