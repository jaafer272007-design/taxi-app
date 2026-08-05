import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../contact/contact_link.dart';
import '../contact/link_launcher.dart';
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
/// This is the ONE and ONLY FILE that touches the map library (`flutter_map` +
/// `latlong2`) — it holds both map surfaces: [AppMapPicker] (choose a point)
/// and [AppMapView] (look at one). Their public interfaces speak only in
/// [LocationPoint] + injected services, so the rest of the app never imports a
/// map type. To move to another provider (e.g. Google Maps) later, replace the
/// internals of THIS file — the booking flow and everything else stay
/// unchanged. (See CLAUDE.md → "Map picker".)
///
/// The read-only view lives here rather than in a file of its own precisely
/// BECAUSE of that rule: a second file drawing tiles would be a second import
/// of `flutter_map`, and the containment would be gone the moment it was
/// written.
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

/// Default zoom for both map surfaces — street level, close enough that a
/// door-to-door pickup point means something.
const double _kZoom = 15;
const String _kOsmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class _AppMapPickerState extends State<AppMapPicker> {
  static const double _zoom = _kZoom;
  static const String _osmUrl = _kOsmUrl;

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
                borderRadius: context.radii.chipAll,
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
        borderRadius: context.radii.fieldLgAll,
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

// ─── Read-only view ─────────────────────────────────────────────────────────

/// Somebody else's point on a map: no pin to drag, no point to confirm — just
/// "here is where they are, take me there".
///
/// This is what turns a reverse-geocoded neighbourhood into a usable pickup.
/// «قرية الغدير السكنية» tells a driver roughly which part of town; it does not
/// tell them which street, and it cannot be navigated to. So the point is drawn
/// where it actually is, and the primary action hands it to a maps app.
///
/// The map is still pannable and zoomable — read-only means the *point* is
/// fixed, not that the driver can't look around it, which is exactly what you
/// do when working out how to approach a street.
class AppMapView extends StatelessWidget {
  const AppMapView({
    super.key,
    required this.point,
    required this.launcher,
    this.title = 'الموقع',
    this.usePlaceholderTiles = false,
    this.onNavigationUnavailable,
  });

  /// The point to show. [LocationPoint.label] may be empty — see [displayLabel].
  final LocationPoint point;

  /// Opens the maps app. Injected so tests assert the URL instead of the OS.
  final LinkLauncher launcher;

  final String title;

  /// Render a neutral placeholder instead of live OSM tiles (goldens/tests).
  final bool usePlaceholderTiles;

  /// Called when no app on the device could open EITHER navigation URI, so the
  /// screen can say so. Without it a failed tap is indistinguishable from a
  /// tap that did not register.
  final VoidCallback? onNavigationUnavailable;

  /// What to call this point when the label is missing.
  ///
  /// Reverse geocoding fails often enough — offline, rate-limited, or simply a
  /// road Nominatim has no name for — that "no label" is a normal state, and an
  /// empty line where an address should be tells the driver nothing at all.
  /// Coordinates are worse than a street name and far better than a blank: they
  /// can be read aloud over the phone and pasted into any maps app.
  static String displayLabel(LocationPoint point) {
    final label = point.label.trim();
    if (label.isNotEmpty) return label;
    return '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}';
  }

  /// True when [displayLabel] fell back to raw coordinates — the caller renders
  /// those LTR, since they are a machine format, not Arabic prose.
  static bool isCoordinateFallback(LocationPoint point) =>
      point.label.trim().isEmpty;

  Future<void> _navigate() async {
    final opened = await openFirst(launcher, ContactLink.navigation(point));
    if (!opened) onNavigationUnavailable?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final center = LatLng(point.lat, point.lng);

    return AppScaffold(
      title: title,
      padded: false,
      bottomBar: _ViewBar(point: point, onNavigate: _navigate),
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: colors.surfaceMuted)),
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: _kZoom,
                minZoom: 4,
                maxZoom: 18,
              ),
              children: [
                if (!usePlaceholderTiles)
                  TileLayer(
                    urlTemplate: _kOsmUrl,
                    userAgentPackageName: 'com.taxi.app',
                  ),
                // A real marker anchored to the coordinates, NOT the picker's
                // screen-centre pin: this point does not move with the map, and
                // drawing it in the middle of the screen would suggest it does.
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: space.xl3,
                      height: space.xl3,
                      alignment: Alignment.topCenter,
                      child: Icon(AppIcons.mapPin,
                          size: space.xl2, color: colors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PositionedDirectional(
            start: space.sm,
            bottom: space.sm,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.82),
                borderRadius: context.radii.chipAll,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: space.sm, vertical: space.xs),
                child: Text('© OpenStreetMap',
                    style:
                        context.text.caption.copyWith(color: colors.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The address, its coordinates, and the hand-off to a maps app.
class _ViewBar extends StatelessWidget {
  const _ViewBar({required this.point, required this.onNavigate});

  final LocationPoint point;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final label = AppMapView.displayLabel(point);
    final isCoords = AppMapView.isCoordinateFallback(point);

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
                  Text(
                    label,
                    // Coordinates are a Western-digit machine format; forcing
                    // LTR keeps "31.99900, 44.31480" from being reordered into
                    // nonsense inside the RTL line.
                    textDirection: isCoords ? TextDirection.ltr : null,
                    style: isCoords
                        ? context.text.bodyStrong.tabular
                            .copyWith(color: colors.textPrimary)
                        : context.text.bodyStrong
                            .copyWith(color: colors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Only when the label IS a name: repeating the coordinates
                  // under themselves would be noise.
                  if (!isCoords) ...[
                    SizedBox(height: space.xs),
                    Text(
                      '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}',
                      textDirection: TextDirection.ltr,
                      style: context.text.caption.tabular
                          .copyWith(color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: space.md),
        AppButton(
          label: 'الاتجاهات في تطبيق الخرائط',
          icon: AppIcons.navigation,
          onPressed: onNavigate,
        ),
      ],
    );
  }
}

/// Push the read-only map view as a route. The app depends on THIS +
/// [AppMapView], never on a map library.
Future<void> showMapView(
  BuildContext context, {
  required LocationPoint point,
  required LinkLauncher launcher,
  String title = 'الموقع',
  VoidCallback? onNavigationUnavailable,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => AppMapView(
        point: point,
        launcher: launcher,
        title: title,
        onNavigationUnavailable: onNavigationUnavailable,
      ),
    ),
  );
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
