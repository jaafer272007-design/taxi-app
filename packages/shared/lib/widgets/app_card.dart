import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A surface container with the standard radius, border and soft card shadow.
/// Optionally tappable (with press feedback).
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.muted = false,
    this.bordered = true,
    this.elevated = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Use the recessed [AppColors.surfaceMuted] fill.
  final bool muted;

  /// Draw the hairline border.
  final bool bordered;

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

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: widget.padding ?? EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radii.lgAll,
        border: widget.bordered
            ? Border.all(color: colors.border, width: 1)
            : null,
        boxShadow: widget.elevated && !widget.muted
            ? context.elevation.card
            : null,
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
