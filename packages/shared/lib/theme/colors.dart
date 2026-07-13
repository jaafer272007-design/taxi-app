import 'package:flutter/material.dart';

/// Semantic color tokens — the single source of truth for every color in the
/// rider, driver and admin apps.
///
/// Screens and widgets must read colors from `context.colors.*`, never from a
/// raw hex literal. A full re-skin is a change to the [light] / [dark] values
/// in THIS file only.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.onInfo,
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

  /// Brand / primary action color.
  final Color primary;

  /// Primary color while an action is pressed (darker for tactile feedback).
  final Color primaryPressed;

  /// Foreground drawn on top of [primary].
  final Color onPrimary;

  /// Secondary emphasis / highlight.
  final Color accent;

  /// Foreground drawn on top of [accent].
  final Color onAccent;

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;
  final Color info;
  final Color onInfo;

  /// Primary body / heading text.
  final Color textPrimary;

  /// Secondary text (labels, captions with emphasis).
  final Color textSecondary;

  /// Muted text (placeholders, disabled, hints).
  final Color textMuted;

  /// App background (behind scrollable content).
  final Color background;

  /// Raised surface (cards, sheets, app bars).
  final Color surface;

  /// A slightly recessed surface (input fills, muted rows).
  final Color surfaceMuted;

  /// Foreground drawn on top of [surface] / [background].
  final Color onSurface;

  /// Default hairline border.
  final Color border;

  /// Stronger border for emphasis / focus.
  final Color borderStrong;

  /// Scrim behind modals / bottom sheets.
  final Color overlay;

  /// LIGHT theme palette.
  static const AppColors light = AppColors(
    primary: Color(0xFF2563EB),
    primaryPressed: Color(0xFF1D4ED8),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFF59E0B),
    onAccent: Color(0xFF7A3D00),
    success: Color(0xFF16A34A),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFFD97706),
    onWarning: Color(0xFFFFFFFF),
    danger: Color(0xFFDC2626),
    onDanger: Color(0xFFFFFFFF),
    info: Color(0xFF2563EB),
    onInfo: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F5F9),
    onSurface: Color(0xFF0F172A),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    overlay: Color(0x800F172A),
  );

  /// DARK theme palette. Status colors are lightened so they keep >= 4.5:1
  /// contrast against the dark surfaces.
  static const AppColors dark = AppColors(
    primary: Color(0xFF3B82F6),
    primaryPressed: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFFBBF24),
    onAccent: Color(0xFF3A1D00),
    success: Color(0xFF22C55E),
    onSuccess: Color(0xFF04120A),
    warning: Color(0xFFF59E0B),
    onWarning: Color(0xFF231400),
    danger: Color(0xFFF87171),
    onDanger: Color(0xFF2A0606),
    info: Color(0xFF60A5FA),
    onInfo: Color(0xFF04121F),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    background: Color(0xFF0B1220),
    surface: Color(0xFF111A2E),
    surfaceMuted: Color(0xFF1E293B),
    onSurface: Color(0xFFF1F5F9),
    border: Color(0xFF24324A),
    borderStrong: Color(0xFF334155),
    overlay: Color(0xB3020617),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryPressed,
    Color? onPrimary,
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? info,
    Color? onInfo,
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
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
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
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
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
