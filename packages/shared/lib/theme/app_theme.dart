import 'package:flutter/material.dart';

import 'colors.dart';
import 'elevation.dart';
import 'radius.dart';
import 'spacing.dart';
import 'typography.dart';

export 'colors.dart';
export 'elevation.dart';
export 'radius.dart';
export 'spacing.dart';
export 'typography.dart';

/// Assembles the light and dark [ThemeData] for every app in the platform and
/// wires the design tokens in as [ThemeExtension]s so they are reachable from
/// `context.colors`, `context.text`, `context.space`, `context.radii` and
/// `context.elevation`.
///
/// A full re-skin (colors, fonts, page styling) is a change to the token files
/// only — screens never touch raw values.
abstract final class AppTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        colors: AppColors.light,
        elevation: AppElevation.light,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        colors: AppColors.dark,
        elevation: AppElevation.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required AppElevation elevation,
  }) {
    final typography = AppTypography.build(colors.textPrimary);
    const spacing = AppSpacing.standard;
    const radii = AppRadii.standard;

    // Seed guarantees every ColorScheme slot is populated (robust across
    // Flutter versions); we then pin the slots our tokens own.
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
    ).copyWith(
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.onDanger,
      surface: colors.surface,
      onSurface: colors.onSurface,
      surfaceContainerHighest: colors.surfaceMuted,
      outline: colors.border,
      outlineVariant: colors.borderStrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      dividerColor: colors.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: typography.toTextTheme(),
      // The apps are Arabic-first; the family is applied through the tokens,
      // but set it here too so any stray Material text matches.
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: typography.h2,
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        typography,
        spacing,
        radii,
        elevation,
      ],
    );
  }
}

/// Ergonomic access to the design tokens from any [BuildContext].
///
/// ```dart
/// Container(
///   padding: EdgeInsets.all(context.space.lg),
///   decoration: BoxDecoration(
///     color: context.colors.surface,
///     borderRadius: context.radii.mdAll,
///     boxShadow: context.elevation.card,
///   ),
///   child: Text('مرحبا', style: context.text.title),
/// )
/// ```
extension AppThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);

  AppColors get colors =>
      theme.extension<AppColors>() ?? AppColors.light;

  AppTypography get text =>
      theme.extension<AppTypography>() ??
      AppTypography.build(AppColors.light.textPrimary);

  AppSpacing get space =>
      theme.extension<AppSpacing>() ?? AppSpacing.standard;

  AppRadii get radii =>
      theme.extension<AppRadii>() ?? AppRadii.standard;

  AppElevation get elevation =>
      theme.extension<AppElevation>() ?? AppElevation.light;

  bool get isDark => theme.brightness == Brightness.dark;
}
