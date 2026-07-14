import 'package:dio/dio.dart';

/// Turns coordinates into a short human label. Abstracted so the map picker can
/// run without one (tests) or with a different provider later.
abstract interface class ReverseGeocoder {
  /// A short Arabic label for the point, or `null` if none is available (the
  /// caller then falls back to a generic label + coordinates).
  Future<String?> label(double lat, double lng);
}

/// A geocoder that always returns `null` — used in tests and when reverse
/// geocoding is disabled.
class NullReverseGeocoder implements ReverseGeocoder {
  const NullReverseGeocoder();

  @override
  Future<String?> label(double lat, double lng) async => null;
}

/// Reverse geocoding via OpenStreetMap's free Nominatim service. Returns a short
/// label built from the nearest address parts; `null` on any error (so the
/// picker degrades gracefully to coordinates).
///
/// Note: Nominatim's usage policy asks for a descriptive User-Agent and light
/// request rates — the picker only calls this when the map settles (debounced).
class NominatimReverseGeocoder implements ReverseGeocoder {
  NominatimReverseGeocoder({
    Dio? dio,
    this.userAgent = 'taxi-app-pooled/1.0',
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final String userAgent;

  static const _addressKeys = [
    'road',
    'neighbourhood',
    'suburb',
    'city_district',
    'city',
    'town',
    'village',
  ];

  @override
  Future<String?> label(double lat, double lng) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': lat,
          'lon': lng,
          'zoom': 16,
          'accept-language': 'ar',
        },
        options: Options(headers: {'User-Agent': userAgent}),
      );
      final data = res.data;
      if (data == null) return null;

      final address = data['address'];
      if (address is Map<String, dynamic>) {
        final parts = <String>[];
        for (final key in _addressKeys) {
          final value = address[key];
          if (value is String && value.trim().isNotEmpty) {
            parts.add(value.trim());
          }
          if (parts.length >= 2) break;
        }
        if (parts.isNotEmpty) return parts.join('، ');
      }

      final display = data['display_name'];
      if (display is String && display.trim().isNotEmpty) {
        return display.split(',').take(2).map((s) => s.trim()).join('، ');
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
