import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The **route rail** — Masar's signature motif.
///
/// A filled origin dot, a dashed vertical run, and a saffron destination ring.
/// It replaces the "من / إلى" label pairs everywhere a trip appears, so intercity
/// direction reads at a glance in RTL without depending on the words.
///
/// ```
///  ●   النجف
///  ┊
///  ◎   كربلاء
/// ```
///
/// [RouteRail] lays the rail out beside [origin] / [destination] content and
/// stretches it to whatever height that content needs.
///
/// ## Contrast
///
/// The two endpoints carry the meaning, so both are held to >= 4.5:1 on every
/// surface they can sit on:
///
/// * origin dot — `primary`: 7.03 background / 7.93 surface / 6.48 surfaceMuted
///   (light), 9.01 / 8.07 / 7.06 (dark).
/// * destination ring — `accentText`: 5.55 / 6.26 / 5.11 (light),
///   10.32 / 9.25 / 8.08 (dark). Note this is `accentText`, **not** `accent`:
///   the raw saffron is 2.60:1 as ink and cannot draw a meaningful graphic.
///   In dark mode the two tokens are the same value, so dark matches the
///   hand-off exactly.
/// * on a `primary` field ([onPrimaryField]) the dot flips to `onPrimary`
///   (7.93 / 7.64) and the ring stays saffron (`accent`, 6.67 on the pine
///   field — a fill-weight surface, so the bright saffron is legible there).
///
/// The dashed run between them is deliberately light (`borderStrong`) and is the
/// one element NOT held to 4.5:1: it is decorative connective tissue, fully
/// redundant with the two endpoints it joins, and drawing it at text contrast
/// would turn a quiet motif into a heavy ladder. Nothing is conveyed by the dash
/// alone.
class RouteRail extends StatelessWidget {
  const RouteRail({
    super.key,
    required this.origin,
    required this.destination,
    this.variant = RouteRailVariant.expanded,
    this.onPrimaryField = false,
    this.divided = false,
  });

  /// Content shown beside the origin dot.
  final Widget origin;

  /// Content shown beside the destination ring.
  final Widget destination;

  final RouteRailVariant variant;

  /// Set when the rail is drawn on a [AppColors.primary] field (the details
  /// hero card), which flips the dot and dash to the on-primary ink.
  final bool onPrimaryField;

  /// Draw a hairline divider between the two blocks (the search-card look).
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final metrics = _RailMetrics.of(variant);

    final dot = onPrimaryField ? colors.onPrimary : colors.primary;
    // On a primary field both endpoints use the on-primary ink and are told
    // apart by shape (filled dot vs stroked ring), the same fill-vs-outline
    // language SeatGlyphs uses.
    //
    // The hand-off draws a saffron ring on its hero card, which works in light
    // (saffron on dark pine, 3.04:1) but NOT in dark: there `primary` is a
    // bright mint, and saffron on it measures 1.15:1 — invisible. Rather than
    // ship a ring that only exists in one theme, both use the on-primary ink
    // (7.93 light / 7.64 dark). A dark-pine *surface* token would let the
    // saffron come back on the hero; that belongs with PR 3's detail screen.
    final ring = onPrimaryField ? colors.onPrimary : colors.accentText;
    final dash = onPrimaryField
        ? colors.onPrimary.withValues(alpha: 0.45)
        : colors.borderStrong;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: metrics.railWidth,
            child: CustomPaint(
              painter: _RouteRailPainter(
                dotColor: dot,
                ringColor: ring,
                dashColor: dash,
                dotSize: metrics.dotSize,
                inset: metrics.inset,
              ),
              // Deliberately childless. `CrossAxisAlignment.stretch` hands this
              // a tight height, so the paint box fills the row; and with no
              // child its *intrinsic* height is 0, which keeps the enclosing
              // IntrinsicHeight driven by the content column. Giving it a
              // SizedBox.expand() child instead would report an infinite
              // intrinsic height and blow up that IntrinsicHeight.
            ),
          ),
          SizedBox(width: space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                origin,
                if (divided) ...[
                  SizedBox(height: space.sm),
                  Divider(height: 1, thickness: 1, color: colors.border),
                  SizedBox(height: space.sm),
                ] else
                  SizedBox(height: metrics.gap),
                destination,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rail sizes. Both come straight from the hand-off: dense list cards draw a
/// 12px rail with 10px dots, everything else a 14px rail with 11px dots.
enum RouteRailVariant {
  /// Dense list rows (bookings list) — 12px rail, 10px dots.
  compact,

  /// Cards and detail heroes — 14px rail, 11px dots.
  expanded,
}

/// Component geometry from the hand-off. These are component metrics, not theme
/// tokens — the token scales (spacing/radius) intentionally do not carry
/// one-off graphic dimensions like an 11px dot or a 2px rail.
class _RailMetrics {
  const _RailMetrics({
    required this.railWidth,
    required this.dotSize,
    required this.inset,
    required this.gap,
  });

  final double railWidth;
  final double dotSize;

  /// Vertical padding before the first dot / after the last ring.
  final double inset;

  /// Space between the origin and destination blocks when undivided.
  final double gap;

  static _RailMetrics of(RouteRailVariant v) => switch (v) {
        RouteRailVariant.compact =>
          const _RailMetrics(railWidth: 12, dotSize: 10, inset: 4, gap: 12),
        RouteRailVariant.expanded =>
          const _RailMetrics(railWidth: 14, dotSize: 11, inset: 6, gap: 18),
      };
}

/// Paints dot → dashed run → ring down the centre of its box.
class _RouteRailPainter extends CustomPainter {
  const _RouteRailPainter({
    required this.dotColor,
    required this.ringColor,
    required this.dashColor,
    required this.dotSize,
    required this.inset,
  });

  final Color dotColor;
  final Color ringColor;
  final Color dashColor;
  final double dotSize;
  final double inset;

  /// 2px run, 4px dash, 5px gap — `repeating-linear-gradient(… 0 4px, transparent 4px 9px)`.
  static const double _runWidth = 2;
  static const double _dashLength = 4;
  static const double _dashGap = 5;

  /// The destination ring is a 3px stroke on an 11px circle.
  static const double _ringStroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = dotSize / 2;
    final topCentre = inset + r;
    final bottomCentre = size.height - inset - r;
    if (bottomCentre <= topCentre) return;

    // Dashed run, drawn first so the endpoints sit on top of it.
    final dashPaint = Paint()
      ..color = dashColor
      ..strokeWidth = _runWidth
      ..strokeCap = StrokeCap.butt;
    var y = topCentre + r;
    final runEnd = bottomCentre - r;
    while (y < runEnd) {
      final end = (y + _dashLength).clamp(y, runEnd);
      canvas.drawLine(Offset(cx, y), Offset(cx, end), dashPaint);
      y += _dashLength + _dashGap;
    }

    // Filled origin dot.
    canvas.drawCircle(
      Offset(cx, topCentre),
      r,
      Paint()..color = dotColor,
    );

    // Saffron destination ring — stroked, so the surface shows through.
    canvas.drawCircle(
      Offset(cx, bottomCentre),
      r - _ringStroke / 2,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringStroke,
    );
  }

  @override
  bool shouldRepaint(_RouteRailPainter old) =>
      old.dotColor != dotColor ||
      old.ringColor != ringColor ||
      old.dashColor != dashColor ||
      old.dotSize != dotSize ||
      old.inset != inset;
}
