import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'driver_trip_api.dart';
import 'driver_trip_models.dart';

enum MyTripsStatus { loading, error, loaded }

/// Loads the driver's own trips (GET /trips/mine) plus the corridors, so each
/// trip row can show its route's city names (trips carry only `corridorId`).
class MyTripsController extends ChangeNotifier {
  MyTripsController({required DriverTripApi api}) : _api = api;

  final DriverTripApi _api;

  MyTripsStatus _status = MyTripsStatus.loading;
  List<DriverTrip> _trips = const [];
  Map<String, Corridor> _corridors = const {};
  String? _error;
  bool _hasLoaded = false;

  MyTripsStatus get status => _status;
  List<DriverTrip> get trips => _trips;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  bool get isEmpty => _trips.isEmpty;

  Corridor? corridorFor(String corridorId) => _corridors[corridorId];

  /// A BACKGROUND refresh: no skeleton, and no error page on failure.
  ///
  /// What pull-to-refresh calls — the [RefreshIndicator] is already the
  /// spinner, so swapping the list for the loading skeleton under the driver's
  /// finger just makes their own trips disappear for a moment.
  Future<void> refreshSilently() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _status = MyTripsStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      final trips = await _api.myTrips();
      final corridors = await _api.getCorridors();
      _trips = trips;
      _corridors = {for (final c in corridors) c.id: c};
      _status = MyTripsStatus.loaded;
      _error = null;
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = MyTripsStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'تعذّر تحميل رحلاتك. حاول مرة أخرى.';
        _status = MyTripsStatus.error;
      }
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }
}
