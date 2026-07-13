import 'package:flutter/widgets.dart';

/// Corner-radius scale. Widgets read `context.radii.md` etc.; never a raw
/// [BorderRadius] literal in a screen.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.pill = 999,
  });

  /// 8
  final double sm;

  /// 12 — default card / input radius.
  final double md;

  /// 16
  final double lg;

  /// 999 — fully rounded (pills, avatars).
  final double pill;

  static const AppRadii standard = AppRadii();

  BorderRadius get smAll => BorderRadius.circular(sm);
  BorderRadius get mdAll => BorderRadius.circular(md);
  BorderRadius get lgAll => BorderRadius.circular(lg);
  BorderRadius get pillAll => BorderRadius.circular(pill);

  @override
  AppRadii copyWith({double? sm, double? md, double? lg, double? pill}) {
    return AppRadii(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    // Radii are constant across themes.
    return this;
  }
}
