import 'package:flutter/material.dart';

import '../format/numerals.dart';
import '../theme/app_theme.dart';

/// A tab in [FloatingPillNav].
class FloatingPillNavItem {
  const FloatingPillNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;

  /// Unread count drawn on the icon. Zero draws nothing — a badge showing "٠"
  /// is a badge saying "look at me, there is nothing here".
  final int badgeCount;
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
  }) : assert(items.length >= 2 && items.length <= 5,
            'The pill fits 2–5 tabs; beyond that the labels stop fitting.');

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
    // one line; three tabs get the roomier one. Five (the driver, once the
    // notification centre joined the nav) needs tighter still — at 390dp that
    // leaves ~70dp per tab, which fits «إشعارات» at the caption size with room
    // to spare, but not with the four-tab padding.
    final sideInset = items.length >= 5
        ? space.md
        : items.length >= 4
            ? space.lg
            : space.xl;
    final tabPadding = items.length >= 5
        ? space.sm
        : items.length >= 4
            ? space.md
            : space.lg;

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
      // The count belongs in the spoken label too, or a screen reader hears
      // "notifications" and misses the only part that says to go there.
      label: item.badgeCount > 0
          ? '${item.label}، ${formatCount(item.badgeCount)} غير مقروء'
          : item.label,
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
                _BadgedIcon(icon: item.icon, count: item.badgeCount, color: fg),
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

/// A nav icon with an unread count riding on its corner.
///
/// The count is drawn on `danger` rather than `primary`: on the selected tab
/// the icon is already `primary` on `primaryTonal`, and a primary badge on top
/// of that reads as part of the selection state instead of as a count. Danger
/// is the one tone that stays a badge on both selected and unselected tabs.
///
/// Above 9 it becomes «+٩» — three Arabic-Indic digits do not fit a 16dp dot,
/// and past a handful the exact number stops changing what anyone does.
class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    required this.icon,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final int count;
  final Color color;

  /// Diameter of the count bubble.
  static const double _dot = 16;

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon, size: 20, color: color);
    if (count <= 0) return base;

    final colors = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        PositionedDirectional(
          top: -4,
          // The badge sits on the icon's trailing corner, which in an RTL
          // layout is the LEFT — PositionedDirectional, not Positioned.
          end: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: _dot, minHeight: _dot),
            padding: EdgeInsets.symmetric(horizontal: context.space.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.danger,
              borderRadius: BorderRadius.circular(_dot),
              // A ring in the pill's own surface colour, so the badge reads as
              // a separate object when it overlaps the glyph.
              border: Border.all(color: colors.surface, width: 1.5),
            ),
            child: Text(
              count > 9 ? '+${formatCount(9)}' : formatCount(count),
              style: context.text.caption.copyWith(
                color: colors.onDanger,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
