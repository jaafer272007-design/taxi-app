import 'package:flutter/material.dart';

/// Elevation tokens. Widgets read `context.elevation.card`.
///
/// Masar surfaces are warm and soft, so the shadows are tinted with the palette
/// ink (#141C19) rather than a neutral slate/black, and they are built from two
/// layers: a 1px contact shadow that seats the card on the paper, plus a wide,
/// heavily-negative-spread ambient that reads as depth without a grey halo.
///
/// Dark mode cards in the hand-off lean on a 1px border rather than a shadow
/// (a light-ink shadow is invisible on a near-black field), so the dark token is
/// a single deep, diffuse near-black.
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({required this.card, required this.floating});

  /// The default soft card shadow.
  final List<BoxShadow> card;

  /// A stronger lift for elements that float over content — the pill nav bar
  /// and sticky bottom CTAs.
  final List<BoxShadow> floating;

  /// Light theme: warm ink shadows on paper.
  static const AppElevation light = AppElevation(
    card: [
      // 0 1px 2px rgba(20,28,25,.05) — contact.
      BoxShadow(
        color: Color(0x0D141C19),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
      // 0 10px 24px -20px rgba(20,28,25,.6) — ambient.
      BoxShadow(
        color: Color(0x99141C19),
        blurRadius: 24,
        offset: Offset(0, 10),
        spreadRadius: -20,
      ),
    ],
    floating: [
      // 0 14px 34px -14px rgba(20,28,25,.55)
      BoxShadow(
        color: Color(0x8C141C19),
        blurRadius: 34,
        offset: Offset(0, 14),
        spreadRadius: -14,
      ),
    ],
  );

  /// Dark theme: a single deep, diffuse near-black so it still registers.
  static const AppElevation dark = AppElevation(
    card: [
      BoxShadow(
        color: Color(0xB3040807),
        blurRadius: 40,
        offset: Offset(0, 18),
        spreadRadius: -26,
      ),
    ],
    floating: [
      BoxShadow(
        color: Color(0xCC040807),
        blurRadius: 40,
        offset: Offset(0, 16),
        spreadRadius: -18,
      ),
    ],
  );

  @override
  AppElevation copyWith({
    List<BoxShadow>? card,
    List<BoxShadow>? floating,
  }) {
    return AppElevation(
      card: card ?? this.card,
      floating: floating ?? this.floating,
    );
  }

  @override
  AppElevation lerp(ThemeExtension<AppElevation>? other, double t) {
    if (other is! AppElevation) return this;
    return AppElevation(
      card: BoxShadow.lerpList(card, other.card, t) ?? card,
      floating: BoxShadow.lerpList(floating, other.floating, t) ?? floating,
    );
  }
}
