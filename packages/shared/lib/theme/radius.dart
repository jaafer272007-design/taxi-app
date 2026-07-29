import 'package:flutter/material.dart';

/// Corner-radius scale. Widgets read `context.radii.card` etc.; never a raw
/// [BorderRadius] literal in a screen.
///
/// ## Masar geometry
///
/// | token   | value | used for                                    |
/// |---------|-------|---------------------------------------------|
/// | chip    | 12    | chips, small tiles, seat glyphs             |
/// | field   | 14    | compact controls (OTP boxes, day chips)     |
/// | fieldLg | 16    | text inputs                                 |
/// | button  | 18    | the primary CTA                             |
/// | card    | 20    | cards, sheets-as-cards                      |
/// | sheet   | 28    | bottom sheets — **top corners only**        |
/// | pill    | 999   | fully rounded (badges, avatars, floating nav)|
///
/// [sm] / [md] / [lg] are the older generic names, kept so existing call sites
/// keep compiling; they now resolve to the Masar values above, which is what
/// carries the new geometry into the existing screens without editing them.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    this.chip = 12,
    this.field = 14,
    this.fieldLg = 16,
    this.button = 18,
    this.card = 20,
    this.sheet = 28,
    this.pill = 999,
  });

  /// 12 — chips, small tiles.
  final double chip;

  /// 14 — compact controls (OTP boxes, day chips, segmented options).
  final double field;

  /// 16 — text inputs.
  final double fieldLg;

  /// 18 — the primary call-to-action button.
  final double button;

  /// 20 — the default card radius.
  final double card;

  /// 28 — bottom sheets. Apply to the TOP corners only, via [sheetTop].
  final double sheet;

  /// 999 — fully rounded (pills, avatars, the floating nav bar).
  final double pill;

  static const AppRadii standard = AppRadii();

  // ── Generic aliases (legacy names -> Masar geometry) ────────────────────
  /// Legacy alias — resolves to [chip] (12).
  double get sm => chip;

  /// Legacy alias — resolves to [fieldLg] (16).
  double get md => fieldLg;

  /// Legacy alias — resolves to [card] (20).
  double get lg => card;

  BorderRadius get smAll => BorderRadius.circular(sm);
  BorderRadius get mdAll => BorderRadius.circular(md);
  BorderRadius get lgAll => BorderRadius.circular(lg);
  BorderRadius get pillAll => BorderRadius.circular(pill);

  BorderRadius get chipAll => BorderRadius.circular(chip);
  BorderRadius get fieldAll => BorderRadius.circular(field);
  BorderRadius get fieldLgAll => BorderRadius.circular(fieldLg);
  BorderRadius get buttonAll => BorderRadius.circular(button);
  BorderRadius get cardAll => BorderRadius.circular(card);

  /// Bottom-sheet radius — top corners only, flat against the screen edge.
  BorderRadius get sheetTop =>
      BorderRadius.vertical(top: Radius.circular(sheet));

  @override
  AppRadii copyWith({
    double? chip,
    double? field,
    double? fieldLg,
    double? button,
    double? card,
    double? sheet,
    double? pill,
  }) {
    return AppRadii(
      chip: chip ?? this.chip,
      field: field ?? this.field,
      fieldLg: fieldLg ?? this.fieldLg,
      button: button ?? this.button,
      card: card ?? this.card,
      sheet: sheet ?? this.sheet,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    // Radii are constant across themes.
    return this;
  }
}
