import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Composites [AppColors.onPrimary] into the pine field **once**, at [alpha],
/// and returns the resulting opaque colour.
///
/// Hero surfaces (the confirmation screen, the trip-details hero, the driver's
/// earnings card) need a fill that reads as "slightly lighter than the field".
/// Doing that with a live `withValues(alpha: …)` would make the measured
/// contrast depend on whatever happens to be painted behind the widget — the
/// exact failure the opaque `*Tonal` tokens exist to prevent. Blending here
/// gives one fixed colour that `contrast_test.dart` can measure.
Color onPrimaryFill(AppColors colors, double alpha) => Color.alphaBlend(
      colors.onPrimary.withValues(alpha: alpha),
      colors.primary,
    );

/// A small chip that lives on a `primary` field.
///
/// The tonal badge tones (`successTonal`, `infoTonal`, …) are built for the page
/// and card surfaces and are unreadable on pine, so a chip on a hero uses the
/// pre-blended fill above with full `onPrimary` ink — 5.33:1 light, 5.79:1 dark,
/// enforced in `contrast_test.dart`.
class OnPrimaryChip extends StatelessWidget {
  const OnPrimaryChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  /// Alpha of the on-primary ink blended into the field.
  static const double blend = 0.16;

  /// The chip's opaque fill for [colors] — also used by the contrast audit.
  static Color fillOn(AppColors colors) => onPrimaryFill(colors, blend);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.md, vertical: space.xs),
      decoration: BoxDecoration(
        color: fillOn(colors),
        borderRadius: context.radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.onPrimary),
            SizedBox(width: space.xs),
          ],
          Text(
            label,
            style: context.text.caption.copyWith(
              color: colors.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
