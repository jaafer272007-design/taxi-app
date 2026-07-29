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

  group('light components', () => _auditComponents(AppColors.light, 'light'));
  group('dark components', () => _auditComponents(AppColors.dark, 'dark'));

  group('light screens', () => _auditScreens(AppColors.light, 'light'));
  group('dark screens', () => _auditScreens(AppColors.dark, 'dark'));

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

/// Per-component contrast contracts for the Masar widgets added in PR 2.
///
/// The palette audit above already proves each *token* pair, but these pin the
/// specific pairing each component relies on. If someone re-points a widget at a
/// different token, this is what catches it — the palette test would still pass.
void _auditComponents(AppColors c, String label) {
  // Every opaque surface a component can be dropped onto.
  final surfaces = <String, Color>{
    'background': c.background,
    'surface': c.surface,
    'surfaceMuted': c.surfaceMuted,
  };

  void onEverySurface(String component, String part, Color ink) {
    for (final s in surfaces.entries) {
      test('$label: $component — $part on ${s.key}', () {
        final r = _contrast(ink, s.value);
        expect(r, greaterThanOrEqualTo(_aa),
            reason: '$component $part on ${s.key} is '
                '${r.toStringAsFixed(2)}:1');
      });
    }
  }

  // RouteRail — the two endpoints carry the meaning and are held to AA. The
  // dashed run between them is decorative (redundant with its endpoints) and is
  // deliberately excluded.
  onEverySurface('RouteRail', 'origin dot (primary)', c.primary);
  onEverySurface('RouteRail', 'destination ring (accentText)', c.accentText);

  test('$label: RouteRail — both endpoints on a primary field', () {
    // Both the dot and the ring use the on-primary ink here; see the note in
    // route_rail.dart for why the hand-off's saffron ring cannot survive dark
    // mode (it measures 1.15:1 on the bright mint primary).
    final r = _contrast(c.onPrimary, c.primary);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'route rail on a primary field is ${r.toStringAsFixed(2)}:1');
  });

  // SeatGlyphs — taken, free and last-free must all be countable.
  onEverySurface('SeatGlyphs', 'taken (primary)', c.primary);
  onEverySurface('SeatGlyphs', 'free (textMuted)', c.textMuted);
  onEverySurface('SeatGlyphs', 'last free (accentText)', c.accentText);
  onEverySurface('SeatAvailability', 'label (textSecondary)', c.textSecondary);
  onEverySurface('SeatAvailability', 'scarce label (warning)', c.warning);

  // FloatingPillNav sits on its own `surface` fill, with `primaryTonal` behind
  // the active tab.
  test('$label: FloatingPillNav — active tab (primary on primaryTonal)', () {
    final r = _contrast(c.primary, c.primaryTonal);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'active nav tab is ${r.toStringAsFixed(2)}:1');
  });
  test('$label: FloatingPillNav — inactive tab (textMuted on surface)', () {
    final r = _contrast(c.textMuted, c.surface);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'inactive nav tab is ${r.toStringAsFixed(2)}:1');
  });

  // RouteSearchCard — the single-card route picker. Its contents sit on
  // `surface` (the card), and the swap control on `primaryTonal`.
  test('$label: RouteSearchCard — city name on the card', () {
    expect(_contrast(c.textPrimary, c.surface), greaterThanOrEqualTo(_aa));
  });
  test('$label: RouteSearchCard — label + placeholder on the card', () {
    final r = _contrast(c.textMuted, c.surface);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'from/to label and "اختر المدينة" placeholder is '
            '${r.toStringAsFixed(2)}:1');
  });
  test('$label: RouteSearchCard — swap icon (primary on primaryTonal)', () {
    final r = _contrast(c.primary, c.primaryTonal);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'swap control is ${r.toStringAsFixed(2)}:1');
  });

  // TripCard headline + secondary price.
  onEverySurface('TripCard', 'departure time (textPrimary)', c.textPrimary);
  onEverySurface('TripCard', 'price (primary)', c.primary);
  onEverySurface('TripCard', 'caption (textMuted)', c.textMuted);
}

/// Per-**screen** contrast contracts for the layouts restructured in PR 3.
///
/// `packages/shared` cannot import the apps, so the few composed fills the
/// screens build (a pre-blended tint on a pine field) are reproduced here with
/// the same constants the screens expose. If a screen changes its blend, the
/// constant here has to move with it — which is the point: an alpha that drifts
/// silently is exactly the failure mode the opaque-tonal rule exists to stop.
void _auditScreens(AppColors c, String label) {
  void pair(String what, Color ink, Color fill) {
    test('$label: $what', () {
      final r = _contrast(ink, fill);
      expect(r, greaterThanOrEqualTo(_aa),
          reason: '$what is ${r.toStringAsFixed(2)}:1, below $_aa:1');
    });
  }

  // ── Booking screen — the seat picker ──────────────────────────────────────
  // Three tile states, each an opaque fill. The unavailable tile is a real
  // recessed surface rather than an opacity wash, so it stays *readable* while
  // reading as dead.
  pair('booking seat tile — selected (onPrimary on primary)',
      c.onPrimary, c.primary);
  pair('booking seat tile — available (textSecondary on surface)',
      c.textSecondary, c.surface);
  pair('booking seat tile — unavailable (textMuted on surfaceMuted)',
      c.textMuted, c.surfaceMuted);

  // ── Booking screen — the cash note and the error banner ───────────────────
  pair('booking cash note (warning on warningTonal)', c.warning, c.warningTonal);
  pair('booking error banner (danger on dangerTonal)', c.danger, c.dangerTonal);

  // ── Confirmation screen — the full-bleed pine field ───────────────────────
  pair('confirmation hero copy (onPrimary on primary)', c.onPrimary, c.primary);
  test('$label: confirmation badge (onPrimary on the pre-blended fill)', () {
    // Mirrors BookingConfirmationScreen's badge: onPrimary at 14% composited
    // into primary ONCE, so the ratio cannot drift with what sits behind it.
    final fill =
        Color.alphaBlend(c.onPrimary.withValues(alpha: 0.14), c.primary);
    final r = _contrast(c.onPrimary, fill);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'confirmation badge is ${r.toStringAsFixed(2)}:1');
  });
  pair('confirmation recap fare (primary on background)', c.primary,
      c.background);

  // ── My bookings — the upcoming/past filter ────────────────────────────────
  // The selected pill inverts: page-background ink on a textPrimary fill, the
  // highest-contrast pairing the palette has.
  pair('bookings filter — selected (background on textPrimary)', c.background,
      c.textPrimary);
  pair('bookings filter — unselected (textSecondary on surface)',
      c.textSecondary, c.surface);

  // ── Trip details — the pine hero ──────────────────────────────────────────
  pair('trip details hero (onPrimary on primary)', c.onPrimary, c.primary);
  test('$label: trip details hero chip (onPrimary on the pre-blended fill)',
      () {
    // Mirrors TripDetailsScreen.heroChipBlend.
    final fill =
        Color.alphaBlend(c.onPrimary.withValues(alpha: 0.16), c.primary);
    final r = _contrast(c.onPrimary, fill);
    expect(r, greaterThanOrEqualTo(_aa),
        reason: 'trip details hero chip is ${r.toStringAsFixed(2)}:1');
  });
  pair('trip details eligibility note (info on infoTonal)', c.info, c.infoTonal);
  pair('trip details book bar price (primary on background)', c.primary,
      c.background);
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
