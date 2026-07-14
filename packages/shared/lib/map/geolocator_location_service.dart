import 'package:geolocator/geolocator.dart';

import 'location_point.dart';
import 'location_service.dart';

/// The production [LocationService], backed by the `geolocator` plugin.
///
/// This is the ONLY file in the codebase that imports `geolocator` — swapping
/// the location backend is a change here alone. Handles the permission dance and
/// maps every failure mode to a [LocationStatus] (never throws).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({this.myLocationLabel = 'موقعي الحالي'});

  /// Label attached to a successfully-resolved current position.
  final String myLocationLabel;

  @override
  Future<LocationResult> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(LocationStatus.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationStatus.deniedForever);
      }

      final pos = await Geolocator.getCurrentPosition();
      return LocationResult.ok(LocationPoint(
        lat: pos.latitude,
        lng: pos.longitude,
        label: myLocationLabel,
      ));
    } catch (_) {
      return const LocationResult(LocationStatus.error);
    }
  }
}
