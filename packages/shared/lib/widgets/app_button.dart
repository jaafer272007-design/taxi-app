import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Visual variants for [AppButton].
enum AppButtonVariant { primary, secondary, ghost, danger }

/// Size variants — both keep a touch target >= 48dp.
enum AppButtonSize { regular, small }

/// The one button used across rider, driver and admin.
///
/// Token-driven: colors, radius, spacing and type all come from the theme.
/// Provides press feedback (background darkens + slight scale), a loading
/// state (spinner, non-interactive) and a disabled state (dimmed).
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.regular,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Optional leading icon (from `AppIcons`).
  final IconData? icon;

  /// When true, shows a spinner and blocks taps.
  final bool loading;

  /// Stretch to the full available width.
  final bool expand;

  bool get _enabled => onPressed != null && !loading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final space = context.space;

    final minHeight = widget.size == AppButtonSize.regular ? 52.0 : 44.0;
    final hPad = widget.size == AppButtonSize.regular ? space.xl2 : space.lg;
    final gap = space.sm;

    final style = _styleFor(colors);
    final bg = _pressed ? style.pressedBackground : style.background;

    final textStyle = context.text.bodyStrong.copyWith(color: style.foreground);

    Widget content;
    if (widget.loading) {
      content = SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(style.foreground),
        ),
      );
    } else {
      final children = <Widget>[
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 20, color: style.foreground),
          SizedBox(width: gap),
        ],
        Flexible(
          child: Text(
            widget.label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ];
      content = Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      );
    }

    final button = AnimatedScale(
      scale: _pressed && widget._enabled ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: BoxConstraints(minHeight: minHeight, minWidth: minHeight),
        padding: EdgeInsets.symmetric(horizontal: hPad),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radii.pillAll,
          border: style.border == null
              ? null
              : Border.all(color: style.border!, width: 1.5),
        ),
        child: content,
      ),
    );

    return Opacity(
      opacity: widget._enabled ? 1 : 0.5,
      child: Semantics(
        button: true,
        enabled: widget._enabled,
        label: widget.label,
        child: GestureDetector(
          onTapDown: widget._enabled ? (_) => _setPressed(true) : null,
          onTapUp: widget._enabled ? (_) => _setPressed(false) : null,
          onTapCancel: widget._enabled ? () => _setPressed(false) : null,
          onTap: widget._enabled ? widget.onPressed : null,
          behavior: HitTestBehavior.opaque,
          child: widget.expand
              ? SizedBox(width: double.infinity, child: button)
              : button,
        ),
      ),
    );
  }

  _ButtonStyle _styleFor(AppColors c) {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return _ButtonStyle(
          background: c.primary,
          pressedBackground: c.primaryPressed,
          foreground: c.onPrimary,
        );
      case AppButtonVariant.danger:
        return _ButtonStyle(
          background: c.danger,
          pressedBackground: Color.lerp(c.danger, Colors.black, 0.14)!,
          foreground: c.onDanger,
        );
      case AppButtonVariant.secondary:
        return _ButtonStyle(
          background: c.surface,
          pressedBackground: c.surfaceMuted,
          foreground: c.primary,
          border: c.borderStrong,
        );
      case AppButtonVariant.ghost:
        return _ButtonStyle(
          background: Colors.transparent,
          pressedBackground: c.surfaceMuted,
          foreground: c.primary,
        );
    }
  }
}

class _ButtonStyle {
  const _ButtonStyle({
    required this.background,
    required this.pressedBackground,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color pressedBackground;
  final Color foreground;
  final Color? border;
}
