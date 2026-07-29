import 'package:flutter/material.dart';

/// Semantic color tokens — the single source of truth for every color in the
/// rider, driver and admin apps.
///
/// Screens and widgets must read colors from `context.colors.*`, never from a
/// raw hex literal. A full re-skin is a change to the [light] / [dark] values
/// in THIS file only.
///
/// ## Palette: "Masar" (مَسار)
///
/// Warm paper surfaces, pine + saffron. Light mode is a paper field (#F4F1EA)
/// with white cards; dark mode is a near-black pine field (#0A100E) with
/// slightly-lifted cards.
///
/// ## Accessibility — locked rule: every text pair is >= 4.5:1 (WCAG AA normal)
///
/// Measured with the WCAG 2.x relative-luminance formula. Every foreground
/// token was checked against all three background tokens (background, surface,
/// surfaceMuted), against the fill it sits on for the `on*` inks, and against
/// the opaque tonal fills that [AppBadge] / [AppButton] actually render.
/// Worst case: **light 4.57**, **dark 4.61**.
///
/// ```
/// LIGHT             background   surface  surfaceMuted
///   textPrimary          15.39     17.36         14.19
///   textSecondary         6.28      7.09          5.79
///   textMuted             4.96      5.59          4.57
///   primary               7.03      7.93          6.48
///   accentText            5.55      6.26          5.11
///   success               4.96      5.60          4.58
///   warning               5.14      5.80          4.74
///   danger                5.23      5.90          4.82
///   info                  6.26      7.06          5.77
///   onPrimary on primary 7.93   onAccent on accent 6.67
///   onSuccess/onWarning/onDanger/onInfo on their fills: 5.60 / 5.80 / 5.90 / 7.06
///   tone on its *Tonal background (badges, pills, dangerTonal button):
///     primary 6.92 · success 4.77 · warning 5.05 · danger 4.92 · info 5.99
///   neutral badge (textSecondary on surfaceMuted)          5.79
///
/// DARK              background   surface  surfaceMuted
///   textPrimary          16.93     15.17         13.26
///   textSecondary         7.77      6.96          6.09
///   textMuted             5.88      5.27          4.61
///   primary               9.01      8.07          7.06
///   accentText           10.32      9.25          8.08
///   success               8.51      7.62          6.67
///   warning               8.97      8.04          7.03
///   danger                7.51      6.72          5.88
///   info                  8.49      7.60          6.65
///   onPrimary on primary 7.64   onAccent on accent 8.75
///   onSuccess/onWarning/onDanger/onInfo on their fills: 8.26 / 8.48 / 7.17 / 8.15
///   tone on its *Tonal background:
///     primary 6.56 · success 6.48 · warning 7.40 · danger 6.56 · info 6.91
///   neutral badge (textSecondary on surfaceMuted)          6.09
///   dangerTonal button pressed                             6.06
/// ```
///
/// `contrast_test.dart` recomputes every one of these pairs from the shipped
/// tokens and fails the build if any drops below 4.5:1, so the *rule* is
/// enforced rather than merely documented. It asserts the 4.5:1 floor, not the
/// exact figures printed above — treat the numbers as a snapshot, and re-measure
/// before relying on the headroom any single pair appears to have.
///
/// ### Deviations from the raw design hand-off (each one forced by that rule)
///
/// * **[accent] is a FILL color only.** #DE8F27 as text/icon ink is 2.60:1 on
///   white — it can never be text. It stays exactly #DE8F27 for fills (dark ink
///   on it passes at 6.67), and [accentText] #8A5410 is the saffron used for any
///   accent-colored *text or icon*.
/// * **[warning] #B87514 -> #8E5A0F.** The hand-off value is 3.75:1 on white.
///   Darkened along its own hue until it clears on all three surfaces.
/// * **[textMuted] #98A49E -> #5D6B65.** The hand-off value is 2.29:1 — by far
///   the worst offender, and it is the most-used ink in the codebase.
/// * **[textSecondary] #5D6B65 -> #4F5B56.** Not requested, but forced: the
///   hand-off's own secondary sits *at* the threshold (4.45:1 on surfaceMuted),
///   so a third, lighter level that also clears 4.5:1 is mathematically
///   impossible beneath it. Rather than collapse to two indistinguishable
///   levels, the ramp shifts one step darker: secondary darkens, and muted
///   inherits the design's original #5D6B65. Three legible levels survive.
/// * **[surfaceMuted] #EAE5DA -> #ECE8DE.** A 2% luminance nudge (imperceptible)
///   so the locked #5D6B65 ink clears 4.5:1 on it. Without this, the *neutral*
///   badge — `textSecondary` on `surfaceMuted` — ships at 4.45:1.
/// * **[success] #1E7A4F -> #1D764D.** Not flagged in the brief; caught by the
///   audit at 4.34:1 on surfaceMuted. A barely-visible darkening clears it.
/// * **dark [textMuted] #697872 -> #82928B.** The only dark-mode hex that moves.
///   The brief called this a "nudge" from 4.14:1, but 4.14 is its ratio against
///   the dark *background* only; on surface it is 3.71:1 and on surfaceMuted
///   3.24:1, so clearing 4.5:1 on all three took a real step, not a nudge.
///
/// Non-text tokens ([border], [borderStrong]) are decorative hairlines and are
/// deliberately not held to the 4.5:1 text rule.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.onInfo,
    required this.primaryTonal,
    required this.successTonal,
    required this.warningTonal,
    required this.dangerTonal,
    required this.infoTonal,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.onSurface,
    required this.border,
    required this.borderStrong,
    required this.overlay,
  });

  /// Brand / primary action color. Pine green.
  final Color primary;

  /// Primary color while an action is pressed (darker for tactile feedback).
  final Color primaryPressed;

  /// Foreground drawn on top of [primary].
  final Color onPrimary;

  /// Saffron highlight — **fills only** (chips, the destination ring, badges).
  /// Never use this as text or icon ink; use [accentText] for that.
  final Color accent;

  /// Foreground drawn on top of an [accent] fill. Dark ink by necessity —
  /// white on saffron is only 2.6:1.
  final Color onAccent;

  /// The saffron used when the accent must be *ink* (text or an icon) on a
  /// page/card surface. Darker than [accent] so it clears 4.5:1.
  final Color accentText;

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;
  final Color info;
  final Color onInfo;

  /// Soft, **opaque** tinted backgrounds for a status shown at low emphasis —
  /// the badge/pill fills and the `dangerTonal` button. The matching *solid*
  /// token ([success], [warning], [danger], [info], [primary]) is the ink drawn
  /// on top of it.
  ///
  /// These are opaque on purpose. Deriving a tint with
  /// `tone.withValues(alpha: …)` composites over whatever happens to be behind
  /// the widget, so the same badge measured 4.61:1 on a white card but only
  /// 3.82:1 on the warm paper background — a silent, position-dependent
  /// accessibility failure. Opaque tokens make the pair fixed and testable.
  final Color primaryTonal;
  final Color successTonal;
  final Color warningTonal;
  final Color dangerTonal;
  final Color infoTonal;

  /// Primary body / heading text.
  final Color textPrimary;

  /// Secondary text (labels, captions with emphasis).
  final Color textSecondary;

  /// Muted text (placeholders, disabled, hints).
  final Color textMuted;

  /// App background (behind scrollable content). The warm paper field.
  final Color background;

  /// Raised surface (cards, sheets, app bars).
  final Color surface;

  /// A slightly recessed surface (input fills, muted rows, past-trip cards).
  final Color surfaceMuted;

  /// Foreground drawn on top of [surface] / [background].
  final Color onSurface;

  /// Default hairline border.
  final Color border;

  /// Stronger border for emphasis / focus.
  final Color borderStrong;

  /// Scrim behind modals / bottom sheets.
  final Color overlay;

  /// LIGHT theme palette — warm paper, pine and saffron.
  static const AppColors light = AppColors(
    primary: Color(0xFF0E5C4A),
    primaryPressed: Color(0xFF0A4638),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFDE8F27),
    onAccent: Color(0xFF141C19),
    accentText: Color(0xFF8A5410),
    success: Color(0xFF1D764D),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFF8E5A0F),
    onWarning: Color(0xFFFFFFFF),
    danger: Color(0xFFB33A2E),
    onDanger: Color(0xFFFFFFFF),
    info: Color(0xFF1F5F7A),
    onInfo: Color(0xFFFFFFFF),
    primaryTonal: Color(0xFFEAF1EE),
    successTonal: Color(0xFFE2F0E9),
    warningTonal: Color(0xFFF8EEDD),
    dangerTonal: Color(0xFFF7E7E5),
    infoTonal: Color(0xFFE4EEF3),
    textPrimary: Color(0xFF141C19),
    textSecondary: Color(0xFF4F5B56),
    textMuted: Color(0xFF5D6B65),
    background: Color(0xFFF4F1EA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFECE8DE),
    onSurface: Color(0xFF141C19),
    border: Color(0xFFE4DFD4),
    borderStrong: Color(0xFFD5CEC0),
    overlay: Color(0x80141C19),
  );

  /// DARK theme palette — near-black pine field, mint primary, warm saffron.
  static const AppColors dark = AppColors(
    primary: Color(0xFF45C6A2),
    primaryPressed: Color(0xFF35B18F),
    onPrimary: Color(0xFF06251D),
    accent: Color(0xFFEFB35F),
    onAccent: Color(0xFF06251D),
    // On dark surfaces the saffron is already 9.25:1 as ink, so the fill color
    // doubles as the text color — no darker variant is needed.
    accentText: Color(0xFFEFB35F),
    success: Color(0xFF43C287),
    onSuccess: Color(0xFF04160E),
    warning: Color(0xFFE5A54A),
    onWarning: Color(0xFF1E1405),
    danger: Color(0xFFEE8478),
    onDanger: Color(0xFF2A0A06),
    info: Color(0xFF66B6DB),
    onInfo: Color(0xFF04161E),
    primaryTonal: Color(0xFF14312A),
    successTonal: Color(0xFF102E22),
    warningTonal: Color(0xFF2A2114),
    dangerTonal: Color(0xFF321512),
    infoTonal: Color(0xFF12262E),
    textPrimary: Color(0xFFECF2EF),
    textSecondary: Color(0xFF9AA8A2),
    textMuted: Color(0xFF82928B),
    background: Color(0xFF0A100E),
    surface: Color(0xFF141D1A),
    surfaceMuted: Color(0xFF1D2925),
    onSurface: Color(0xFFECF2EF),
    border: Color(0xFF233029),
    borderStrong: Color(0xFF33443E),
    overlay: Color(0xB3040807),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryPressed,
    Color? onPrimary,
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? info,
    Color? onInfo,
    Color? primaryTonal,
    Color? successTonal,
    Color? warningTonal,
    Color? dangerTonal,
    Color? infoTonal,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? onSurface,
    Color? border,
    Color? borderStrong,
    Color? overlay,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      primaryTonal: primaryTonal ?? this.primaryTonal,
      successTonal: successTonal ?? this.successTonal,
      warningTonal: warningTonal ?? this.warningTonal,
      dangerTonal: dangerTonal ?? this.dangerTonal,
      infoTonal: infoTonal ?? this.infoTonal,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      onSurface: onSurface ?? this.onSurface,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      primaryTonal: Color.lerp(primaryTonal, other.primaryTonal, t)!,
      successTonal: Color.lerp(successTonal, other.successTonal, t)!,
      warningTonal: Color.lerp(warningTonal, other.warningTonal, t)!,
      dangerTonal: Color.lerp(dangerTonal, other.dangerTonal, t)!,
      infoTonal: Color.lerp(infoTonal, other.infoTonal, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}
