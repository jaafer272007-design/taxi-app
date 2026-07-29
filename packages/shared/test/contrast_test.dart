import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// Enforces the locked accessibility rule: **every foreground/background token
/// pair is >= 4.5:1** (WCAG 2.x AA for normal-size text).
///
/// This is the reason the Masar palette deviates from the raw hand-off in a few
/// places — see the deviation list in `colors.dart`. Keeping it as a test rather
/// than a comment means a future re-skin cannot quietly reintroduce a failure:
/// change a token to something illegible and CI goes red.
void main() {
  group('light palette', () => _auditPalette(AppColors.light, 'light'));
  group('dark palette', () => _auditPalette(AppColors.dark, 'dark'));

  test('the audit uses the WCAG formula (sanity check on known values)', () {
    // Black on white is the canonical 21:1.
    expect(_contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01));
    // The hand-off's saffron as ink on white — the 2.6:1 that forced accentText.
    expect(_contrast(const Color(0xFFDE8F27), const Color(0xFFFFFFFF)),
        closeTo(2.60, 0.02));
  });
}

/// Minimum ratio for normal-size text.
const double _aa = 4.5;

void _auditPalette(AppColors c, String label) {
  final surfaces = <String, Color>{
    'background': c.background,
    'surface': c.surface,
    'surfaceMuted': c.surfaceMuted,
  };

  // Every ink that can be drawn on a page or card surface.
  final inks = <String, Color>{
    'textPrimary': c.textPrimary,
    'textSecondary': c.textSecondary,
    'textMuted': c.textMuted,
    'primary': c.primary,
    'accentText': c.accentText,
    'success': c.success,
    'warning': c.warning,
    'danger': c.danger,
    'info': c.info,
  };

  for (final ink in inks.entries) {
    for (final bg in surfaces.entries) {
      test('$label: ${ink.key} on ${bg.key}', () {
        final r = _contrast(ink.value, bg.value);
        expect(r, greaterThanOrEqualTo(_aa),
            reason: '$label ${ink.key} on ${bg.key} is '
                '${r.toStringAsFixed(2)}:1, below $_aa:1');
      });
    }
  }

  // `on*` inks against the solid fill they are drawn on.
  final onFills = <String, (Color ink, Color fill)>{
    'onPrimary/primary': (c.onPrimary, c.primary),
    'onAccent/accent': (c.onAccent, c.accent),
    'onSuccess/success': (c.onSuccess, c.success),
    'onWarning/warning': (c.onWarning, c.warning),
    'onDanger/danger': (c.onDanger, c.danger),
    'onInfo/info': (c.onInfo, c.info),
  };
  for (final e in onFills.entries) {
    test('$label: ${e.key}', () {
      final r = _contrast(e.value.$1, e.value.$2);
      expect(r, greaterThanOrEqualTo(_aa),
          reason: '$label ${e.key} is ${r.toStringAsFixed(2)}:1');
    });
  }

  // Tonal pairs exactly as AppBadge / AppButton(dangerTonal) render them.
  final tonals = <String, (Color ink, Color fill)>{
    'primary/primaryTonal': (c.primary, c.primaryTonal),
    'success/successTonal': (c.success, c.successTonal),
    'warning/warningTonal': (c.warning, c.warningTonal),
    'danger/dangerTonal': (c.danger, c.dangerTonal),
    'info/infoTonal': (c.info, c.infoTonal),
    'neutral badge (textSecondary/surfaceMuted)': (
      c.textSecondary,
      c.surfaceMuted
    ),
  };
  for (final e in tonals.entries) {
    test('$label: tonal ${e.key}', () {
      final r = _contrast(e.value.$1, e.value.$2);
      expect(r, greaterThanOrEqualTo(_aa),
          reason: '$label tonal ${e.key} is ${r.toStringAsFixed(2)}:1');
    });
  }

  test('$label: dangerTonal button keeps AA while pressed', () {
    // Mirrors AppButton._styleFor(dangerTonal).pressedBackground.
    final pressed = Color.lerp(c.dangerTonal, c.danger, 0.05)!;
    final r = _contrast(c.danger, pressed);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: '$label pressed dangerTonal is ${r.toStringAsFixed(2)}:1');
  });

  test('$label: the three text levels stay visually distinct', () {
    // The whole reason textSecondary was darkened: a three-level ramp where
    // every level still clears AA. Guard that they do not collapse together.
    final primaryL = c.textPrimary.computeLuminance();
    final secondaryL = c.textSecondary.computeLuminance();
    final mutedL = c.textMuted.computeLuminance();
    expect(_contrast(c.textPrimary, c.textSecondary), greaterThan(1.6),
        reason: 'textPrimary and textSecondary are too close');
    expect(_contrast(c.textSecondary, c.textMuted), greaterThan(1.15),
        reason: 'textSecondary and textMuted collapsed into one level');
    // Monotonic ramp: primary is the strongest ink, muted the weakest.
    if (c.background.computeLuminance() > 0.5) {
      expect(primaryL, lessThan(secondaryL));
      expect(secondaryL, lessThan(mutedL));
    } else {
      expect(primaryL, greaterThan(secondaryL));
      expect(secondaryL, greaterThan(mutedL));
    }
  });
}

/// WCAG 2.x contrast ratio. [Color.computeLuminance] is Flutter's
/// implementation of the same relative-luminance formula.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
