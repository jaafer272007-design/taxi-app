import 'package:shared/shared.dart';

/// A scriptable [LocationService] for tests — no `geolocator` plugin.
class FakeLocationService implements LocationService {
  FakeLocationService(this.result);

  FakeLocationService.ok(LocationPoint point)
      : result = LocationResult.ok(point);

  FakeLocationService.denied()
      : result = const LocationResult(LocationStatus.denied);

  final LocationResult result;
  int calls = 0;

  @override
  Future<LocationResult> currentLocation() async {
    calls++;
    return result;
  }
}
