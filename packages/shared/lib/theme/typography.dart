import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type scale — Arabic-first, built on the "Cairo" family (excellent Arabic +
/// Latin coverage). Every text style in the apps comes from
/// `context.text.title` etc.; never a raw `TextStyle(fontSize: …)` in a screen.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.display,
    required this.h1,
    required this.h2,
    required this.title,
    required this.body,
    required this.bodyStrong,
    required this.label,
    required this.caption,
  });

  /// 28 / w700 — hero numbers, splash headings.
  final TextStyle display;

  /// 24 / w700 — screen title.
  final TextStyle h1;

  /// 20 / w600 — section heading.
  final TextStyle h2;

  /// 18 / w600 — card / list title.
  final TextStyle title;

  /// 16 / w400 — default body.
  final TextStyle body;

  /// 16 / w600 — emphasized body / button label.
  final TextStyle bodyStrong;

  /// 14 / w500 — form labels, chips.
  final TextStyle label;

  /// 13 / w400 — captions, helper text.
  final TextStyle caption;

  /// Comfortable reading line-height for Arabic.
  static const double _lineHeight = 1.5;

  /// Build the scale in [color]. Called once per theme (light/dark) so the
  /// same font sizes/weights are shared and only the ink color differs.
  factory AppTypography.build(Color color) {
    TextStyle style(double size, FontWeight weight) => GoogleFonts.cairo(
          fontSize: size,
          fontWeight: weight,
          height: _lineHeight,
          color: color,
        );

    return AppTypography(
      display: style(28, FontWeight.w700),
      h1: style(24, FontWeight.w700),
      h2: style(20, FontWeight.w600),
      title: style(18, FontWeight.w600),
      body: style(16, FontWeight.w400),
      bodyStrong: style(16, FontWeight.w600),
      label: style(14, FontWeight.w500),
      caption: style(13, FontWeight.w400),
    );
  }

  /// Map onto Material's [TextTheme] so stock widgets pick up the scale too.
  TextTheme toTextTheme() {
    return TextTheme(
      displayLarge: display,
      displayMedium: display,
      displaySmall: h1,
      headlineLarge: h1,
      headlineMedium: h1,
      headlineSmall: h2,
      titleLarge: h2,
      titleMedium: title,
      titleSmall: label,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: bodyStrong,
      labelMedium: label,
      labelSmall: caption,
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? title,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? label,
    TextStyle? caption,
  }) {
    return AppTypography(
      display: display ?? this.display,
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      title: title ?? this.title,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      label: label ?? this.label,
      caption: caption ?? this.caption,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      display: TextStyle.lerp(display, other.display, t)!,
      h1: TextStyle.lerp(h1, other.h1, t)!,
      h2: TextStyle.lerp(h2, other.h2, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
    );
  }
}

/// Numeric styling helpers for prices, times and phone numbers. Latin digits
/// with tabular figures keep columns aligned and read cleanly in an RTL layout.
extension TabularFigures on TextStyle {
  /// Force Latin digits + tabular (monospaced) figures — use for IQD prices,
  /// clock times and +964 phone numbers.
  TextStyle get tabular => copyWith(
        fontFeatures: const [
          FontFeature.tabularFigures(),
          FontFeature.liningFigures(),
        ],
        // Digits render left-to-right even inside an RTL paragraph.
        textBaseline: TextBaseline.alphabetic,
      );
}
