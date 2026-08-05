import 'package:flutter/material.dart';

import 'trip_api.dart';
import 'trip_models.dart';
import 'package:shared/shared.dart';

enum TripSearchStatus { initial, loading, results, empty, error }

/// How the results list is ordered.
///
/// Now that each driver sets their own price, two trips on the same route can
/// cost different amounts — so "which is cheapest" is a real question a rider
/// can ask, and [TripSort.price] is the answer.
enum TripSort {
  /// Earliest departure first. The default: most riders are choosing when to
  /// travel, not shopping.
  departure,

  /// Cheapest per seat first.
  price,
}

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
  TripSort _sort = TripSort.departure;

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

  /// The current result ordering. Defaults to [TripSort.departure].
  TripSort get sort => _sort;

  /// Re-order the results already on screen. Sorting is a local operation — it
  /// must never cost a round trip, so this does NOT re-run the search.
  void setSort(TripSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    _results = _sorted(_results);
    notifyListeners();
  }

  /// Order a result list by the current [sort].
  ///
  /// Both orderings fall back to the other key so the list is deterministic:
  /// with two trips at the same price, the earlier one comes first, which is
  /// what a rider comparing them would expect.
  List<TripSummary> _sorted(List<TripSummary> trips) {
    final out = List<TripSummary>.of(trips);
    switch (_sort) {
      case TripSort.departure:
        out.sort((a, b) {
          final byTime = a.departureTime.compareTo(b.departureTime);
          return byTime != 0 ? byTime : a.pricePerSeat.compareTo(b.pricePerSeat);
        });
      case TripSort.price:
        out.sort((a, b) {
          final byPrice = a.pricePerSeat.compareTo(b.pricePerSeat);
          return byPrice != 0
              ? byPrice
              : a.departureTime.compareTo(b.departureTime);
        });
    }
    return out;
  }

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
        // Prefer the flagship pair over whichever corridor happens to sort
        // first — with all 306 pairs served, "first" is alphabetical accident.
        final preferred = _corridors.firstWhere(
          (c) =>
              c.originCity == kDefaultOriginCity &&
              c.destCity == kDefaultDestCity,
          orElse: () => _corridors.first,
        );
        _origin = preferred.originCity;
        _dest = preferred.destCity;
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

  /// Re-run the current search as a BACKGROUND refresh.
  ///
  /// This is what the poll and pull-to-refresh call. It differs from [search]
  /// in exactly two ways, and both matter:
  ///
  ///  * it never shows the loading skeleton — the rider is reading the list,
  ///    and replacing it with shimmer every 15 seconds would be unusable;
  ///  * **it never clears the results on failure.** A dropped request leaves
  ///    the last good list exactly where it was and says nothing. The rider
  ///    did not ask for this refresh and must not be told it failed.
  Future<void> refreshSilently() => search(silent: true);

  /// Run the search for the current form. Results come back in the current
  /// [sort] order.
  Future<void> search({bool silent = false}) async {
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

    if (!silent) {
      _status = TripSearchStatus.loading;
      _error = null;
      notifyListeners();
    }

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

      // _sorted copies before sorting — never mutate the list the API handed us
      // (it may be unmodifiable).
      _results = _sorted(
        await _api.searchTrips(
          corridorId: corridor.id,
          date: day,
          fromTime: from,
          toTime: to,
          tripType: _tripType,
          driverGender: _driverGender,
        ),
      );
      _status =
          _results.isEmpty ? TripSearchStatus.empty : TripSearchStatus.results;
      _error = null;
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = TripSearchStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'حدث خطأ. حاول مرة أخرى.';
        _status = TripSearchStatus.error;
      }
    } finally {
      notifyListeners();
    }
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
