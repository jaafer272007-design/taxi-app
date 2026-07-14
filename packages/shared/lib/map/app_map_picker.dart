import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_scaffold.dart';
import 'location_point.dart';
import 'location_service.dart';
import 'reverse_geocoder.dart';

/// A full-screen "move the map, pin stays centered" location picker.
///
/// ─── SWAPPABLE MAP PROVIDER ───────────────────────────────────────────────
/// This is the ONE and ONLY widget that touches the map library (`flutter_map`
/// + `latlong2`). Its public interface speaks only in [LocationPoint] +
/// injected services, so the rest of the app never imports a map type. To move
/// to another provider (e.g. Google Maps) later, replace the internals of THIS
/// file — the booking flow and everything else stay unchanged. (See CLAUDE.md →
/// "Map picker".)
/// ──────────────────────────────────────────────────────────────────────────
class AppMapPicker extends StatefulWidget {
  const AppMapPicker({
    super.key,
    required this.initialCenter,
    required this.onPointSelected,
    required this.locationService,
    this.reverseGeocoder,
    this.title = 'حدّد الموقع',
    this.fallbackLabel = 'النقطة المحددة',
    this.usePlaceholderTiles = false,
  });

  /// Where the map opens centered (e.g. the trip corridor's city centre).
  final LocationPoint initialCenter;

  /// Called with the chosen point when the rider taps "تأكيد النقطة".
  final ValueChanged<LocationPoint> onPointSelected;

  /// Resolves the device location for the "استخدم موقعي" button.
  final LocationService locationService;

  /// Optional: turns the centred coordinates into a readable label. When null,
  /// the picker shows [fallbackLabel] + coordinates.
  final ReverseGeocoder? reverseGeocoder;

  final String title;
  final String fallbackLabel;

  /// Render a neutral placeholder instead of live OSM tiles — used by golden
  /// tests / previews (and anywhere network tiles are undesirable).
  final bool usePlaceholderTiles;

  @override
  State<AppMapPicker> createState() => _AppMapPickerState();
}

class _AppMapPickerState extends State<AppMapPicker> {
  static const double _zoom = 15;
  static const String _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  final MapController _map = MapController();
  late final ValueNotifier<LatLng> _center = ValueNotifier<LatLng>(
    LatLng(widget.initialCenter.lat, widget.initialCenter.lng),
  );

  late String _label = widget.initialCenter.label.trim().isNotEmpty
      ? widget.initialCenter.label.trim()
      : widget.fallbackLabel;

  bool _locating = false;
  String? _locationMessage;
  Timer? _geocodeDebounce;
  int _geocodeSeq = 0;

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _center.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center.value = camera.center;
    if (widget.reverseGeocoder == null) return;
    _geocodeDebounce?.cancel();
    _geocodeDebounce =
        Timer(const Duration(milliseconds: 600), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    final geocoder = widget.reverseGeocoder;
    if (geocoder == null) return;
    final seq = ++_geocodeSeq;
    final center = _center.value;
    final resolved = await geocoder.label(center.latitude, center.longitude);
    if (!mounted) return;
    if (seq != _geocodeSeq) return; // a newer request superseded this one
    setState(() => _label = (resolved != null && resolved.trim().isNotEmpty)
        ? resolved.trim()
        : widget.fallbackLabel);
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    final result = await widget.locationService.currentLocation();
    if (!mounted) return;
    if (result.isOk) {
      final point = result.point!;
      _center.value = LatLng(point.lat, point.lng);
      _map.move(_center.value, _zoom);
      setState(() {
        _locating = false;
        _label = point.label.trim().isNotEmpty
            ? point.label.trim()
            : widget.fallbackLabel;
      });
      unawaited(_maybeGeocode());
    } else {
      setState(() {
        _locating = false;
        _locationMessage = result.arabicMessage;
      });
    }
  }

  Future<void> _maybeGeocode() async {
    if (widget.reverseGeocoder != null) await _reverseGeocode();
  }

  void _confirm() {
    final center = _center.value;
    final label = _label.trim().isEmpty ? widget.fallbackLabel : _label.trim();
    widget.onPointSelected(
      LocationPoint(lat: center.latitude, lng: center.longitude, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppScaffold(
      title: widget.title,
      padded: false,
      bottomBar: _ConfirmBar(
        center: _center,
        label: _label,
        onConfirm: _confirm,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: colors.surfaceMuted)),
          Positioned.fill(child: _buildMap()),
          // Fixed centre pin (screen-space, so it stays put while the map moves).
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: space.xl2),
                child: Icon(AppIcons.mapPin,
                    size: space.xl2, color: colors.primary),
              ),
            ),
          ),
          PositionedDirectional(
            top: space.md,
            end: space.md,
            child: AppButton(
              label: 'استخدم موقعي',
              icon: AppIcons.mapPin,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              expand: false,
              loading: _locating,
              onPressed: _locating ? null : _useMyLocation,
            ),
          ),
          if (_locationMessage != null)
            PositionedDirectional(
              top: space.md,
              start: space.md,
              end: space.md + space.xl4 + space.xl2,
              child: _LocationBanner(message: _locationMessage!),
            ),
          // OpenStreetMap tile attribution (required by the OSM usage policy).
          PositionedDirectional(
            start: space.sm,
            bottom: space.sm,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.82),
                borderRadius: context.radii.smAll,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: space.sm, vertical: space.xs),
                child: Text('© OpenStreetMap',
                    style: context.text.caption
                        .copyWith(color: colors.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _center.value,
        initialZoom: _zoom,
        minZoom: 4,
        maxZoom: 18,
        onPositionChanged: _onPositionChanged,
      ),
      children: [
        if (!widget.usePlaceholderTiles)
          TileLayer(
            urlTemplate: _osmUrl,
            userAgentPackageName: 'com.taxi.app',
          ),
      ],
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.center,
    required this.label,
    required this.onConfirm,
  });

  final ValueNotifier<LatLng> center;
  final String label;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.mapPin, size: space.xl, color: colors.primary),
            SizedBox(width: space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('النقطة المحددة',
                      style: context.text.caption
                          .copyWith(color: colors.textMuted)),
                  SizedBox(height: space.xs),
                  Text(label,
                      style: context.text.bodyStrong
                          .copyWith(color: colors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: space.xs),
                  ValueListenableBuilder<LatLng>(
                    valueListenable: center,
                    builder: (_, c, __) => Text(
                      '${c.latitude.toStringAsFixed(5)}, ${c.longitude.toStringAsFixed(5)}',
                      textDirection: TextDirection.ltr,
                      style: context.text.caption.tabular
                          .copyWith(color: colors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: space.md),
        AppButton(label: 'تأكيد النقطة', icon: AppIcons.check, onPressed: onConfirm),
      ],
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: context.radii.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.warning, size: space.lg, color: colors.warning),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(message,
                style: context.text.caption.copyWith(color: colors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Push the map picker as a route and resolve to the chosen [LocationPoint]
/// (null if the rider backs out). The app depends on THIS + [AppMapPicker], not
/// on any map library.
Future<LocationPoint?> showMapPicker(
  BuildContext context, {
  required LocationPoint initialCenter,
  required LocationService locationService,
  ReverseGeocoder? reverseGeocoder,
  String title = 'حدّد الموقع',
  String fallbackLabel = 'النقطة المحددة',
}) {
  return Navigator.of(context).push<LocationPoint>(
    MaterialPageRoute<LocationPoint>(
      builder: (routeContext) => AppMapPicker(
        initialCenter: initialCenter,
        locationService: locationService,
        reverseGeocoder: reverseGeocoder,
        title: title,
        fallbackLabel: fallbackLabel,
        onPointSelected: (point) => Navigator.of(routeContext).pop(point),
      ),
    ),
  );
}
