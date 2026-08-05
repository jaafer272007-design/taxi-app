import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import '../trip/driver_trip_api.dart';
import '../trip/driver_trip_models.dart';

enum EarningsStatus { loading, error, loaded }

/// Loads the driver's cash earnings for both ranges (today + all-time) from
/// GET /driver/earnings. The all-time response also carries the per-trip
/// breakdown rows (date + amount; the API exposes no route names, only tripId).
class EarningsController extends ChangeNotifier {
  EarningsController({required DriverTripApi api}) : _api = api;

  final DriverTripApi _api;

  EarningsStatus _status = EarningsStatus.loading;
  DriverEarnings? _today;
  DriverEarnings? _all;
  String? _error;
  bool _hasLoaded = false;

  List<EarningsDay> _days = const [];

  EarningsStatus get status => _status;
  int get todayTotal => _today?.total ?? 0;
  int get allTimeTotal => _all?.total ?? 0;
  List<EarningsRecord> get records => _all?.records ?? const [];
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  bool get isEmpty => records.isEmpty;

  /// The all-time ledger grouped by Baghdad calendar day, newest day first and
  /// newest row first within each day.
  List<EarningsDay> get days => _days;

  /// How many trips produced [todayTotal].
  ///
  /// Taken from the **server's** today-range rows, not from filtering the
  /// all-time list against the phone's clock: the total and the count then come
  /// from the same query, so they cannot disagree across a midnight boundary or
  /// a mis-set device timezone.
  int get todayTripCount => _today?.records.length ?? 0;

  /// How many trips produced [allTimeTotal].
  int get tripCount => records.length;

  /// A BACKGROUND refresh: no skeleton, and no error page on failure.
  ///
  /// What pull-to-refresh calls. Cash figures are the last thing that should
  /// vanish and be replaced by "حدث خطأ" because one request dropped.
  Future<void> refreshSilently() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _status = EarningsStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        _api.earnings(range: 'today'),
        _api.earnings(range: 'all'),
      ]);
      _today = results[0];
      _all = results[1];
      _days = _groupByDay(_all!.records);
      _status = EarningsStatus.loaded;
      _error = null;
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = EarningsStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'تعذّر تحميل أرباحك. حاول مرة أخرى.';
        _status = EarningsStatus.error;
      }
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Buckets records into Baghdad calendar days, newest first.
  ///
  /// The API returns a flat list in no guaranteed order, so both the days and
  /// the rows inside them are sorted here rather than trusted.
  static List<EarningsDay> _groupByDay(List<EarningsRecord> records) {
    final buckets = <DateTime, List<EarningsRecord>>{};
    for (final r in records) {
      final t = baghdadTime(r.collectedAt);
      final key = DateTime.utc(t.year, t.month, t.day);
      (buckets[key] ??= <EarningsRecord>[]).add(r);
    }

    final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        () {
          final rows = buckets[k]!
            ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
          return EarningsDay(
            date: k,
            records: List.unmodifiable(rows),
            // Summed from the rows, never read off a separate field — the
            // header a driver checks has to be the arithmetic of what is
            // printed beneath it.
            total: rows.fold(0, (sum, r) => sum + r.amount),
          );
        }(),
    ];
  }
}
