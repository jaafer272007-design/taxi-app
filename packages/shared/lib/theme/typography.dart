import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type scale — Arabic-first, built on the "Cairo" family (excellent Arabic +
/// Latin coverage). Every text style in the apps comes from
/// `context.text.title` etc.; never a raw `TextStyle(fontSize: …)` in a screen.
///
/// ## Masar scale
///
/// | token      | size | weight |
/// |------------|------|--------|
/// | display    | 34   | w800   |
/// | h1         | 26   | w700   |
/// | h2         | 20   | w700   |
/// | title      | 17   | w700   |
/// | body       | 15   | w400   |
/// | bodyStrong | 15   | w700   |
/// | label      | 13   | w600   |
/// | caption    | 12   | w400   |
///
/// The scale leans on weight rather than size for hierarchy — Cairo's w700/w800
/// are strong enough that 17px reads as a title next to 15px body.
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

  /// 34 / w800 — hero numbers (fares, earnings), splash headings.
  final TextStyle display;

  /// 26 / w700 — screen title.
  final TextStyle h1;

  /// 20 / w700 — section heading.
  final TextStyle h2;

  /// 17 / w700 — card / list title.
  final TextStyle title;

  /// 15 / w400 — default body.
  final TextStyle body;

  /// 15 / w700 — emphasized body / button label.
  final TextStyle bodyStrong;

  /// 13 / w600 — form labels, chips.
  final TextStyle label;

  /// 12 / w400 — captions, helper text.
  final TextStyle caption;

  /// Comfortable reading line-height for Arabic. Arabic needs more leading than
  /// Latin (ascenders, descenders and diacritics stack), so running text sits at
  /// 1.5.
  static const double _readingHeight = 1.5;

  /// Headings are set tighter — at 20–26px a 1.5 multiple opens gaps that read
  /// as separate blocks rather than one heading.
  static const double _headingHeight = 1.3;

  /// The display size is a single hero number, not running text; it is set
  /// nearly solid so a fare or a departure time reads as one object.
  static const double _displayHeight = 1.15;

  /// Build the scale in [color]. Called once per theme (light/dark) so the
  /// same font sizes/weights are shared and only the ink color differs.
  factory AppTypography.build(Color color) {
    TextStyle style(
      double size,
      FontWeight weight, {
      double height = _readingHeight,
      double? letterSpacing,
    }) =>
        GoogleFonts.cairo(
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: letterSpacing,
          color: color,
        );

    return AppTypography(
      // Slight negative tracking on the two largest sizes keeps big Arabic
      // numerals from looking loose (matches the hand-off's -.02em / -.01em).
      display: style(34, FontWeight.w800,
          height: _displayHeight, letterSpacing: -0.68),
      h1: style(26, FontWeight.w700,
          height: _headingHeight, letterSpacing: -0.26),
      h2: style(20, FontWeight.w700, height: _headingHeight),
      title: style(17, FontWeight.w700, height: _headingHeight),
      body: style(15, FontWeight.w400),
      bodyStrong: style(15, FontWeight.w700),
      label: style(13, FontWeight.w600),
      caption: style(12, FontWeight.w400),
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

/// Numeric styling helper for figures that must line up in a column.
///
/// Note the numeral *system* is chosen by the formatting helpers in
/// `format/numerals.dart` (Arabic-Indic for display, Western for input), not
/// here — this only controls glyph metrics.
extension TabularFigures on TextStyle {
  /// Monospaced (tabular) figures — use for stacked IQD prices, clock times and
  /// the +964 phone/OTP fields so digits stay in vertical alignment.
  TextStyle get tabular => copyWith(
        fontFeatures: const [
          FontFeature.tabularFigures(),
          FontFeature.liningFigures(),
        ],
        // Digits render left-to-right even inside an RTL paragraph.
        textBaseline: TextBaseline.alphabetic,
      );
}
