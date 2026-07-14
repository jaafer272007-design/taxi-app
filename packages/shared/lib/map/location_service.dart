import 'location_point.dart';

/// Outcome of a device-location request.
enum LocationStatus {
  /// A position was obtained ([LocationResult.point] is set).
  ok,

  /// The user denied the location permission.
  denied,

  /// The permission is permanently denied (must be enabled from settings).
  deniedForever,

  /// Location services are turned off on the device.
  serviceDisabled,

  /// Any other failure (timeout, plugin error).
  error,
}

/// The result of [LocationService.currentLocation].
class LocationResult {
  const LocationResult(this.status, [this.point]);

  const LocationResult.ok(LocationPoint point) : this(LocationStatus.ok, point);

  final LocationStatus status;

  /// Set only when [status] is [LocationStatus.ok].
  final LocationPoint? point;

  bool get isOk => status == LocationStatus.ok && point != null;

  /// A ready-to-show Arabic message for the non-ok statuses (empty when ok).
  String get arabicMessage => switch (status) {
        LocationStatus.ok => '',
        LocationStatus.denied => 'تم رفض إذن الموقع. يمكنك تحريك الخريطة يدوياً.',
        LocationStatus.deniedForever =>
          'إذن الموقع مرفوض دائماً. فعّله من إعدادات الهاتف، أو حرّك الخريطة يدوياً.',
        LocationStatus.serviceDisabled =>
          'خدمة الموقع مغلقة. شغّلها، أو حرّك الخريطة يدوياً.',
        LocationStatus.error =>
          'تعذّر تحديد موقعك. حرّك الخريطة يدوياً لتحديد النقطة.',
      };
}

/// Device-location provider. Abstracted so [AppMapPicker] and tests never touch
/// the `geolocator` plugin directly — the production implementation
/// ([GeolocatorLocationService]) is the only place that imports it.
abstract interface class LocationService {
  /// Request the current device position (handling permission internally).
  Future<LocationResult> currentLocation();
}
