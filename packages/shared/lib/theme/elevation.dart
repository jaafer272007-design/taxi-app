import 'package:flutter/material.dart';

/// Elevation tokens. Phase 1 uses a single soft, low-opacity card shadow —
/// subtle depth, no heavy Material drop shadows. Widgets read
/// `context.elevation.card`.
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({required this.card});

  /// The one soft card shadow used across the apps.
  final List<BoxShadow> card;

  /// Light theme: a faint slate shadow.
  static const AppElevation light = AppElevation(
    card: [
      BoxShadow(
        color: Color(0x140F172A), // ~8% slate-900
        blurRadius: 16,
        offset: Offset(0, 6),
        spreadRadius: -4,
      ),
      BoxShadow(
        color: Color(0x0A0F172A), // ~4% slate-900, tight ambient
        blurRadius: 4,
        offset: Offset(0, 1),
      ),
    ],
  );

  /// Dark theme: deeper, more diffuse so it registers on dark surfaces.
  static const AppElevation dark = AppElevation(
    card: [
      BoxShadow(
        color: Color(0x66020617), // ~40% near-black
        blurRadius: 20,
        offset: Offset(0, 8),
        spreadRadius: -6,
      ),
    ],
  );

  @override
  AppElevation copyWith({List<BoxShadow>? card}) {
    return AppElevation(card: card ?? this.card);
  }

  @override
  AppElevation lerp(ThemeExtension<AppElevation>? other, double t) {
    if (other is! AppElevation) return this;
    return AppElevation(
      card: BoxShadow.lerpList(card, other.card, t) ?? card,
    );
  }
}
