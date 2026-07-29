import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'app_city_field.dart';
import 'app_icons.dart';
import 'route_rail.dart';

/// The route picker as **one card**: the route rail, both city endpoints, and
/// the swap control, all inside a single surface.
///
/// This is what the hand-off specifies, and the shape matters. Two separate
/// bordered fields with a rail floating beside them reads as two unrelated
/// inputs; one card with the rail running down its inside edge reads as a
/// single journey — which is the whole point of the motif.
///
/// ```
/// ┌─────────────────────────────┐
/// │ ●  من                       │
/// │ ┊  النجف            ⇄       │
/// │ ┊  ─────────────            │
/// │ ◎  إلى                      │
/// │    كربلاء                   │
/// └─────────────────────────────┘
/// ```
///
/// Shared by the rider's search and the driver's post-a-trip, which had
/// duplicated this layout (and its swap button) before.
///
/// ## Contrast
///
/// * city name — `textPrimary`, placeholder — `textMuted`, label — `textMuted`,
///   all on `surface`: 17.36 / 5.59 / 5.59 (light), 15.17 / 5.27 / 5.27 (dark).
/// * swap icon — `primary` on `primaryTonal`: 6.92 (light) / 6.56 (dark).
///
/// The swap control is a 40dp circle per the hand-off but carries a 48dp tap
/// target.
class RouteSearchCard extends StatelessWidget {
  const RouteSearchCard({
    super.key,
    required this.origin,
    required this.dest,
    required this.onOriginChanged,
    required this.onDestChanged,
    required this.onSwap,
    this.enabled = true,
  });

  /// Selected city keys (English storage values), or null when unset.
  final String? origin;
  final String? dest;

  final ValueChanged<String> onOriginChanged;
  final ValueChanged<String> onDestChanged;
  final VoidCallback onSwap;

  final bool enabled;

  /// Identifies the swap control, so tests can assert its tap target without
  /// depending on the semantics tree being enabled.
  static const Key swapKey = ValueKey('route-search-card.swap');

  @override
  Widget build(BuildContext context) {
    final space = context.space;

    return AppCard(
      // The hand-off insets the swap side slightly less than the rail side.
      padding: EdgeInsetsDirectional.fromSTEB(
        space.lg,
        space.lg,
        space.md,
        space.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: RouteRail(
              divided: true,
              origin: AppCityField(
                bare: true,
                label: 'من',
                cityKey: origin,
                onChanged: onOriginChanged,
                enabled: enabled,
                excludeKey: dest,
              ),
              destination: AppCityField(
                bare: true,
                label: 'إلى',
                cityKey: dest,
                onChanged: onDestChanged,
                enabled: enabled,
                excludeKey: origin,
              ),
            ),
          ),
          SizedBox(width: space.sm),
          _SwapButton(key: swapKey, onTap: enabled ? onSwap : null),
        ],
      ),
    );
  }
}

/// The circular swap control that lives inside the route card.
class _SwapButton extends StatelessWidget {
  const _SwapButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  /// Hand-off circle size; the tap target around it is 48.
  static const double _circle = 40;
  static const double _target = 48;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'اعكس الاتجاه',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _target,
          height: _target,
          child: Center(
            child: Container(
              width: _circle,
              height: _circle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryTonal,
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.swap,
                size: context.space.xl,
                color: colors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
