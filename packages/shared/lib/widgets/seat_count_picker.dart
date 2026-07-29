import 'package:flutter/material.dart';

import '../format/numerals.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'app_icons.dart';

/// **Tap the number of seats you want.**
///
/// Replaces the ± stepper on both sides of the app: the rider picks how many
/// seats to book, the driver picks how many to offer. A stepper hides its
/// ceiling — you discover it by pressing `+` and having nothing happen — while a
/// row of tiles shows the whole range at once and draws the counts you cannot
/// have as *visibly dead*.
///
/// Tiles above [max] use the recessed `surfaceMuted` fill with `textMuted` ink
/// rather than an opacity wash. A translucent tile composites over whatever is
/// behind it, so its contrast stops being predictable; the recessed pair is
/// fixed at 4.57:1 light / 4.61:1 dark and still legible, which is the point —
/// a dead tile should read as "not available", not as "broken rendering".
class SeatCountPicker extends StatelessWidget {
  const SeatCountPicker({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.offered = 4,
    this.hint,
  });

  /// The currently selected count.
  final int value;

  /// The highest selectable count. Tiles above this are drawn dead.
  final int max;

  final ValueChanged<int> onChanged;

  /// How many tiles to draw. Anything above [max] is shown but not selectable,
  /// which is how the ceiling becomes legible.
  final int offered;

  /// Quiet line under the tiles — availability, or the vehicle's capacity.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final hintText = hint;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              for (var n = 1; n <= offered; n++) ...[
                if (n > 1) SizedBox(width: space.sm),
                Expanded(
                  child: _SeatTile(
                    n: n,
                    selected: value == n,
                    available: n <= max,
                    onTap: n <= max ? () => onChanged(n) : null,
                  ),
                ),
              ],
            ],
          ),
          if (hintText != null) ...[
            SizedBox(height: space.md),
            Text(
              hintText,
              style: context.text.caption.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.n,
    required this.selected,
    required this.available,
    this.onTap,
  });

  final int n;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  /// Hand-off tile height; comfortably above the 48dp minimum.
  static const double _height = 76;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Color bg = selected
        ? colors.primary
        : available
            ? colors.surface
            : colors.surfaceMuted;
    final Color ink = selected
        ? colors.onPrimary
        : available
            ? colors.textSecondary
            : colors.textMuted;
    final Color border = selected ? colors.primary : colors.border;

    return Semantics(
      button: available,
      enabled: available,
      selected: selected,
      label: formatSeats(n),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: context.radii.fieldAll,
            border: Border.all(color: border, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.seat, size: context.space.xl2, color: ink),
              SizedBox(height: context.space.xs),
              Text(formatCount(n),
                  style: context.text.label.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}
