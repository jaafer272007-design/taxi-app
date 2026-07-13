import 'package:flutter/widgets.dart';

/// Spacing scale — a strict 4 / 8 rhythm. Every gap, padding and margin in the
/// apps must come from one of these steps (via `context.space.md` etc.), never
/// a raw number.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 20,
    this.xl2 = 24,
    this.xl3 = 32,
    this.xl4 = 40,
  });

  /// 4
  final double xs;

  /// 8
  final double sm;

  /// 12
  final double md;

  /// 16 — default content padding.
  final double lg;

  /// 20
  final double xl;

  /// 24
  final double xl2;

  /// 32
  final double xl3;

  /// 40
  final double xl4;

  static const AppSpacing standard = AppSpacing();

  /// Square [EdgeInsets] from a scale value.
  EdgeInsets all(double v) => EdgeInsets.all(v);

  /// Horizontal [EdgeInsets] from a scale value.
  EdgeInsets h(double v) => EdgeInsets.symmetric(horizontal: v);

  /// Vertical [EdgeInsets] from a scale value.
  EdgeInsets v(double v) => EdgeInsets.symmetric(vertical: v);

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xl2,
    double? xl3,
    double? xl4,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xl2: xl2 ?? this.xl2,
      xl3: xl3 ?? this.xl3,
      xl4: xl4 ?? this.xl4,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    // Spacing is constant across themes; no interpolation needed.
    return this;
  }
}
