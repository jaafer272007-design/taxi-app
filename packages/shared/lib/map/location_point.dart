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

  /// False for the 0,0 placeholder an API response without coordinates
  /// produces.
  ///
  /// Worth a named getter rather than an inline `lat != 0` at each call site:
  /// 0,0 is Null Island in the Gulf of Guinea, and a map opened there is a
  /// worse answer than no map — so every caller that can open a map has to ask
  /// this first, and the question should read the same everywhere.
  bool get hasCoordinates => lat != 0 || lng != 0;

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
