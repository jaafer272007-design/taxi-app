import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A tab in [FloatingPillNav].
class FloatingPillNavItem {
  const FloatingPillNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The **floating pill nav** — Masar's bottom navigation.
///
/// A 62px pill inset from the screen edges and lifted off the bottom, floating
/// over the content rather than sitting in a bar welded to the frame. This is
/// deliberately *not* a Material [NavigationBar]/[BottomNavigationBar]: those
/// paint a full-width surface with their own elevation, indicator and label
/// behaviour, none of which match the hand-off.
///
/// Selection is shown by a `primaryTonal` pill behind the active tab.
///
/// ## Layout
///
/// The nav positions itself; give it the full width at the bottom of a [Stack]
/// and reserve [reservedSpace] at the bottom of the content so nothing hides
/// underneath:
///
/// ```dart
/// Stack(children: [
///   Padding(
///     padding: EdgeInsets.only(bottom: FloatingPillNav.reservedSpace),
///     child: body,
///   ),
///   const Positioned(left: 0, right: 0, bottom: 0, child: FloatingPillNav(…)),
/// ])
/// ```
///
/// It lifts itself above the system gesture bar using `viewPadding.bottom`, so
/// callers do not need their own [SafeArea].
///
/// ## Contrast
///
/// Every pair, on the two surfaces this nav can sit on (its own `surface` fill,
/// and `primaryTonal` behind the active tab):
///
/// * active icon + label — `primary` on `primaryTonal`: 6.92 (light) / 6.56 (dark).
/// * inactive icon + label — `textMuted` on `surface`: 5.59 (light) / 5.27 (dark).
///
/// The hand-off draws inactive tabs in #98A49E, which is 2.58:1 on white — it
/// was the pre-PR-1 `textMuted` and is exactly the value the palette audit
/// replaced. Using the current `textMuted` keeps the intent and clears AA.
///
/// Every tab is at least 48x48 regardless of how short the label is.
class FloatingPillNav extends StatelessWidget {
  const FloatingPillNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  }) : assert(items.length >= 2 && items.length <= 4,
            'The pill fits 2–4 tabs; beyond that the labels stop fitting.');

  final List<FloatingPillNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Height of the pill itself.
  static const double height = 62;

  /// Gap between the pill and the bottom of the screen.
  static const double bottomInset = 22;

  /// Vertical space a screen must leave free so content is not hidden behind
  /// the floating pill.
  static const double reservedSpace = height + bottomInset + 12;

  /// Minimum tap target (Material + WCAG 2.5.5).
  static const double _minTarget = 48;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final isDark = context.isDark;

    // Four tabs need the tighter inset from the hand-off to keep the labels on
    // one line; three tabs get the roomier one.
    final sideInset = items.length >= 4 ? space.lg : space.xl;
    final tabPadding = items.length >= 4 ? space.md : space.lg;

    // Lift above the gesture bar. viewPadding (not padding) so it still works
    // when the keyboard has consumed the inset.
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        0,
        sideInset,
        bottomInset + safeBottom,
      ),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: context.radii.pillAll,
          // Light lifts with a shadow; dark uses a hairline, because a shadow
          // is invisible on a near-black field (same rule as AppCard).
          border: isDark ? Border.all(color: colors.border, width: 1) : null,
          boxShadow: isDark ? null : context.elevation.floating,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              _Tab(
                item: items[i],
                selected: i == currentIndex,
                horizontalPadding: tabPadding,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.horizontalPadding,
    required this.onTap,
  });

  final FloatingPillNavItem item;
  final bool selected;
  final double horizontalPadding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.primary : colors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: FloatingPillNav._minTarget,
            minHeight: FloatingPillNav._minTarget,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: context.space.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.primaryTonal : Colors.transparent,
              borderRadius: context.radii.pillAll,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 20, color: fg),
                SizedBox(height: context.space.xs),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
