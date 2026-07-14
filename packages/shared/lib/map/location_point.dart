/// A geographic point the rider marks: coordinates + a human label.
///
/// This is the ONLY location type the app depends on — [AppMapPicker] and the
/// location services speak in `LocationPoint`, never in a map-library type
/// (flutter_map's `LatLng`), so the map provider stays swappable.
class LocationPoint {
  const LocationPoint({
    required this.lat,
    required this.lng,
    this.label = '',
  });

  final double lat;
  final double lng;
  final String label;

  LocationPoint copyWith({double? lat, double? lng, String? label}) =>
      LocationPoint(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        label: label ?? this.label,
      );

  @override
  bool operator ==(Object other) =>
      other is LocationPoint &&
      other.lat == lat &&
      other.lng == lng &&
      other.label == label;

  @override
  int get hashCode => Object.hash(lat, lng, label);

  @override
  String toString() => 'LocationPoint($lat, $lng, "$label")';
}
