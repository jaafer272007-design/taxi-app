import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

/// Displays a 0–5 star rating. Read-only by default; pass [onRate] to make it
/// interactive (tap a star to set the value). Fractional values (e.g. 4.5)
/// render a partially-filled star, direction-aware for RTL.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.value,
    this.count = 5,
    this.size = 20,
    this.onRate,
  });

  /// Current rating (may be fractional for display, e.g. 4.5).
  final double value;

  /// Total number of stars.
  final int count;

  final double size;

  /// When provided, tapping star _i_ reports a rating of _i + 1_.
  final ValueChanged<int>? onRate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final active = colors.accent;
    final inactive = colors.borderStrong;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        // Fill fraction of star i: 1 fully filled, 0 empty, in-between partial.
        final fill = (value - i).clamp(0.0, 1.0);

        Widget star = Stack(
          children: [
            Icon(AppIcons.star, size: size, color: inactive),
            if (fill > 0)
              ClipRect(
                clipper: _FillClipper(fill),
                child: Icon(AppIcons.star, size: size, color: active),
              ),
          ],
        );

        star = Padding(
          padding: EdgeInsets.only(left: i == count - 1 ? 0 : space.xs / 2),
          child: star,
        );

        if (onRate == null) return star;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onRate!(i + 1),
          child: Semantics(
            button: true,
            label: '${i + 1}',
            child: star,
          ),
        );
      }),
    );
  }
}

/// Clips a star to [fraction] of its width from the leading (start) edge.
class _FillClipper extends CustomClipper<Rect> {
  const _FillClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FillClipper oldClipper) => oldClipper.fraction != fraction;
}
