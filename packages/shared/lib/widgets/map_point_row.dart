import 'package:flutter/material.dart';

import '../map/app_map_picker.dart' show AppMapView;
import '../map/location_point.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';

/// One end of a door-to-door journey, as a row you can tap to see on a map.
///
/// Shared because the driver and the rider look at the same two points from
/// opposite sides — the driver at where to collect someone, the rider at where
/// they asked to be collected — and the failure mode is identical on both: a
/// label that reverse geocoding never resolved leaves a blank line where an
/// address should be. [AppMapView.displayLabel] gives coordinates instead, and
/// this renders them LTR because they are a machine format, not Arabic prose.
class MapPointRow extends StatelessWidget {
  const MapPointRow({
    super.key,
    required this.title,
    required this.point,
    required this.onTap,
    this.icon = AppIcons.mapPin,
  });

  /// What this end is: «نقطة الانطلاق» / «نقطة النزول».
  final String title;

  final LocationPoint point;

  /// Opens the map view.
  ///
  /// Pass null when the point has no real coordinates
  /// ([LocationPoint.hasCoordinates]) — the row then renders as plain text with
  /// no map affordance. That case is the one an older API row produces, and a
  /// chevron that opens Null Island is worse than no chevron.
  final VoidCallback? onTap;

  final IconData icon;

  bool get _tappable => onTap != null && point.hasCoordinates;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final label = AppMapView.displayLabel(point);
    final isCoords = AppMapView.isCoordinateFallback(point);

    final content = ConstrainedBox(
      // 48dp: the Material minimum, and on the driver's busiest screen this is
      // a primary action.
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: space.lg, color: colors.textMuted),
            SizedBox(width: space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: context.text.caption
                          .copyWith(color: colors.textMuted)),
                  SizedBox(height: space.xs),
                  Text(
                    label,
                    // Coordinates are a Western-digit machine format; forcing
                    // LTR stops the RTL line from reordering them.
                    textDirection: isCoords ? TextDirection.ltr : null,
                    style: isCoords
                        ? context.text.body.tabular
                            .copyWith(color: colors.textSecondary)
                        : context.text.body
                            .copyWith(color: colors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (_tappable) ...[
              SizedBox(width: space.sm),
              // The affordance. Without it the row is indistinguishable from
              // the static text it used to be and nobody discovers the tap —
              // which is also exactly why it is absent when there is no tap.
              Icon(AppIcons.map, size: space.lg, color: colors.primary),
            ],
          ],
        ),
      ),
    );

    if (!_tappable) return content;

    return Semantics(
      button: true,
      // Reads as one sentence to a screen reader instead of four fragments.
      label: '$title: $label. اعرض على الخريطة',
      excludeSemantics: true,
      // `Material(transparency)` around the InkWell, not bare InkWell: ink is
      // painted onto the nearest Material ancestor, and AppCard is a plain
      // AnimatedContainer — so the ripple would render UNDERNEATH the card's
      // opaque background and the row would look unresponsive to the tap.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: context.radii.fieldLgAll,
          child: content,
        ),
      ),
    );
  }
}
