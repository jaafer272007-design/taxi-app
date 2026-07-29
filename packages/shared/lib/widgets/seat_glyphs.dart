import 'package:flutter/material.dart';

import '../format/numerals.dart';
import '../theme/app_theme.dart';

/// **Seat glyphs** — availability drawn as seats rather than spelled out.
///
/// One rounded rect per seat: **filled = taken, outlined = free**. A rider reads
/// a car's fill state at a glance instead of parsing "٣/٤ متاح", and when only
/// one seat is left that last glyph switches to the saffron scarcity stroke.
///
/// ```
///  ▮ ▮ ▯ ▯     two taken, two free
///  ▮ ▮ ▮ ▯     one left — the free glyph turns saffron
/// ```
///
/// ## Contrast
///
/// Both glyph states are meaningful graphics, so both clear 4.5:1 on every
/// surface they can sit on (background / surface / surfaceMuted):
///
/// * taken — `primary`: 7.03 / 7.93 / 6.48 (light), 9.01 / 8.07 / 7.06 (dark).
/// * free — `textMuted`: 4.96 / 5.59 / 4.57 (light), 5.88 / 5.27 / 4.61 (dark).
/// * last free — `accentText`: 5.55 / 6.26 / 5.11 (light),
///   10.32 / 9.25 / 8.08 (dark).
///
/// The hand-off outlines free seats in #C6CFC9, which is 1.61:1 on white — fine
/// as decoration but not for a glyph that has to be *counted*. `textMuted` keeps
/// the same quiet-grey role while staying legible at 13x22, which is the whole
/// point of the motif.
class SeatGlyphs extends StatelessWidget {
  const SeatGlyphs({
    super.key,
    required this.total,
    required this.available,
    this.compact = false,
  });

  /// Seats offered on the trip.
  final int total;

  /// Seats still free. Clamped into `0..total`.
  final int available;

  /// The denser 12x20 variant used inside detail rows.
  final bool compact;

  /// True when the trip is down to its last seat — the scarcity state that
  /// turns the final glyph and its label saffron.
  static bool isScarce(int available) => available == 1;

  /// Arabic availability label, in Arabic-Indic numerals.
  ///
  /// Arabic has a dual form, so two seats is "مقعدان" — not "٢ مقاعد".
  static String label(int available) => switch (available) {
        <= 0 => 'لا مقاعد متاحة',
        1 => 'مقعد واحد فقط',
        2 => 'مقعدان متاحان',
        _ => '${formatCount(available)} مقاعد متاحة',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final free = available.clamp(0, total);
    final taken = total - free;
    final scarce = isScarce(free);

    final w = compact ? _compactWidth : _width;
    final h = compact ? _compactHeight : _height;

    return Semantics(
      label: '${label(free)} من ${formatCount(total)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            _SeatGlyph(
              width: w,
              height: h,
              // Taken seats fill from the front, so the free ones trail.
              filled: i < taken,
              // Only the final remaining seat wears the scarcity stroke.
              color: i < taken
                  ? colors.primary
                  : (scarce ? colors.accentText : colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// Component geometry from the hand-off (13x22, r4, 1.5px stroke, 5px gap).
// These are one-off graphic metrics, not theme tokens.
const double _width = 13;
const double _height = 22;
const double _compactWidth = 12;
const double _compactHeight = 20;
const double _gap = 5;
const double _radius = 4;
const double _stroke = 1.5;

class _SeatGlyph extends StatelessWidget {
  const _SeatGlyph({
    required this.width,
    required this.height,
    required this.filled,
    required this.color,
  });

  final double width;
  final double height;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        border: filled ? null : Border.all(color: color, width: _stroke),
      ),
    );
  }
}

/// [SeatGlyphs] plus its Arabic label — the drop-in replacement for the old
/// "N مقاعد متاحة" pill. The label turns saffron on the last seat, matching the
/// glyph, so scarcity is carried by both colour and wording.
class SeatAvailability extends StatelessWidget {
  const SeatAvailability({
    super.key,
    required this.total,
    required this.available,
    this.compact = false,
  });

  final int total;
  final int available;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final free = available.clamp(0, total);
    final scarce = SeatGlyphs.isScarce(free);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SeatGlyphs(total: total, available: free, compact: compact),
        SizedBox(width: context.space.sm),
        Flexible(
          child: Text(
            SeatGlyphs.label(free),
            style: context.text.label.copyWith(
              // `warning` for scarcity, not `accentText`: the label is running
              // text, and warning is the semantic token for "act soon".
              color: scarce ? colors.warning : colors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
