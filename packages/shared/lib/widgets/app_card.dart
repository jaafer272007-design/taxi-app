import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A surface container at the Masar card radius (20), lifted off the page.
/// Optionally tappable (with press feedback).
///
/// How it is lifted depends on the theme, which is what the hand-off does:
/// a **light** card floats on the warm paper with a soft shadow and no outline,
/// while a **dark** card uses a hairline border and no shadow — an ink shadow is
/// invisible against a near-black field, so the border is what separates the
/// card from the background. [bordered] overrides that per-instance.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.muted = false,
    this.bordered,
    this.elevated = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Use the recessed [AppColors.surfaceMuted] fill.
  final bool muted;

  /// Force the hairline border on/off. Defaults to the theme-driven behaviour
  /// described on the class (border in dark, shadow in light).
  final bool? bordered;

  /// Draw the soft card shadow.
  final bool elevated;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final space = context.space;

    final baseColor = widget.muted ? colors.surfaceMuted : colors.surface;
    final bg = _pressed ? colors.surfaceMuted : baseColor;

    // Dark lifts with a border, light with a shadow. A muted card is recessed
    // rather than raised, so it gets neither.
    final isDark = context.isDark;
    final bordered = widget.bordered ?? (isDark && !widget.muted);
    final shadowed = widget.elevated && !widget.muted && !isDark;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: widget.padding ?? EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radii.cardAll,
        border: bordered ? Border.all(color: colors.border, width: 1) : null,
        boxShadow: shadowed ? context.elevation.card : null,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return card;

    return Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}
