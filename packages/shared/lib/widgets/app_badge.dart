import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Semantic tone for [AppBadge] / [AppPill].
enum AppBadgeTone { neutral, success, warning, danger, info }

/// A small status chip with a soft tinted background. Text-only or with a
/// leading icon. Colors derive from tokens per [tone].
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final AppBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final space = context.space;
    final pair = _toneColors(colors, tone);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.md, vertical: space.xs),
      decoration: BoxDecoration(
        color: pair.background,
        borderRadius: radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: pair.foreground),
            SizedBox(width: space.xs),
          ],
          Text(
            label,
            style: context.text.caption.copyWith(
              color: pair.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill is a badge sized for standalone tags (a touch more padding). Shares
/// the tone palette with [AppBadge].
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final AppBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final space = context.space;
    final pair = _toneColors(colors, tone);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.lg, vertical: space.sm),
      decoration: BoxDecoration(
        color: pair.background,
        borderRadius: radii.pillAll,
        border: Border.all(color: pair.foreground.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: pair.foreground),
            SizedBox(width: space.xs),
          ],
          Text(
            label,
            style: context.text.label.copyWith(color: pair.foreground),
          ),
        ],
      ),
    );
  }
}

class _TonePair {
  const _TonePair(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

_TonePair _toneColors(AppColors c, AppBadgeTone tone) {
  switch (tone) {
    case AppBadgeTone.success:
      return _TonePair(c.success.withValues(alpha: 0.14), c.success);
    case AppBadgeTone.warning:
      return _TonePair(c.warning.withValues(alpha: 0.16), c.warning);
    case AppBadgeTone.danger:
      return _TonePair(c.danger.withValues(alpha: 0.14), c.danger);
    case AppBadgeTone.info:
      return _TonePair(c.info.withValues(alpha: 0.14), c.info);
    case AppBadgeTone.neutral:
      return _TonePair(c.surfaceMuted, c.textSecondary);
  }
}
