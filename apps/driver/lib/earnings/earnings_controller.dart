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

  EarningsStatus get status => _status;
  int get todayTotal => _today?.total ?? 0;
  int get allTimeTotal => _all?.total ?? 0;
  List<EarningsRecord> get records => _all?.records ?? const [];
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  bool get isEmpty => records.isEmpty;

  Future<void> load() async {
    _status = EarningsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.earnings(range: 'today'),
        _api.earnings(range: 'all'),
      ]);
      _today = results[0];
      _all = results[1];
      _status = EarningsStatus.loaded;
    } on ApiException catch (e) {
      _error = e.message;
      _status = EarningsStatus.error;
    } catch (_) {
      _error = 'تعذّر تحميل أرباحك. حاول مرة أخرى.';
      _status = EarningsStatus.error;
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }
}
