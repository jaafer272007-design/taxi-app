import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The per-star fill fractions for a rating [value] over [count] stars.
///
/// Star _i_ (0-based) is filled `1.0` when `value >= i + 1`, `0.0` when
/// `value <= i`, and the fractional remainder in between. So `4.9` over 5 stars
/// yields `[1, 1, 1, 1, 0.9]` — four full stars and a nearly-full fifth, never
/// four empties. Pure and side-effect-free so the fill logic can be unit-tested
/// directly.
List<double> ratingStarFills(double value, {int count = 5}) {
  final v = value.clamp(0.0, count.toDouble());
  return List<double>.generate(count, (i) => (v - i).clamp(0.0, 1.0).toDouble());
}

/// Displays a 0–5 star rating. Read-only by default; pass [onRate] to make it
/// interactive (tap a star to set the value). Stars are drawn as SOLID shapes,
/// so a fractional value (e.g. 4.5) renders a partially-filled star — the filled
/// part grows from the leading (start) edge, so it reads correctly in RTL.
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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final fills = ratingStarFills(value, count: count);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        Widget star = SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _StarPainter(
              fill: fills[i],
              active: active,
              inactive: inactive,
              rtl: rtl,
            ),
          ),
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

/// Paints one solid five-pointed star: the whole star in [inactive], then the
/// [fill] fraction re-painted in [active], clipped from the leading edge
/// ([rtl] flips that edge to the right).
class _StarPainter extends CustomPainter {
  const _StarPainter({
    required this.fill,
    required this.active,
    required this.inactive,
    required this.rtl,
  });

  final double fill;
  final Color active;
  final Color inactive;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _starPath(size);

    final base = Paint()
      ..color = inactive
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, base);

    if (fill <= 0) return;

    canvas.save();
    final w = size.width * fill.clamp(0.0, 1.0);
    // The filled portion grows from the start edge: left in LTR, right in RTL.
    final clip = rtl
        ? Rect.fromLTWH(size.width - w, 0, w, size.height)
        : Rect.fromLTWH(0, 0, w, size.height);
    canvas.clipRect(clip);
    final fg = Paint()
      ..color = active
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fg);
    canvas.restore();
  }

  /// A classic five-pointed star inscribed in [size], starting at the top vertex.
  Path _starPath(Size size) {
    const points = 5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = math.min(size.width, size.height) / 2;
    final inner = outer * 0.42; // inner/outer ratio → a standard star silhouette
    final step = math.pi / points; // angle between successive vertices
    var angle = -math.pi / 2; // first point at the top

    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      angle += step;
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.fill != fill ||
      old.active != active ||
      old.inactive != inactive ||
      old.rtl != rtl;
}
