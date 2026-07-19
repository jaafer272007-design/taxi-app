import 'package:flutter/material.dart';

import '../constants/iraqi_cities.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';

/// A tappable field that shows the selected city and opens the canonical-city
/// picker on tap. Token-driven; used for both the rider search from/to and the
/// driver post-trip from/to.
class AppCityField extends StatelessWidget {
  const AppCityField({
    super.key,
    required this.label,
    required this.cityKey,
    required this.onChanged,
    this.enabled = true,
    this.excludeKey,
  });

  /// Small caption above the value (e.g. "من" / "إلى").
  final String label;

  /// Selected city key (English, stored value) or null when nothing is chosen.
  final String? cityKey;

  final ValueChanged<String> onChanged;
  final bool enabled;

  /// A city that cannot be picked here (e.g. the other endpoint) — prevents
  /// choosing the same origin and destination.
  final String? excludeKey;

  Future<void> _open(BuildContext context) async {
    final picked = await showAppCityPicker(
      context,
      selected: cityKey,
      title: 'اختر المدينة',
      excludeKey: excludeKey,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final hasValue = cityKey != null;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: enabled ? () => _open(context) : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: space.md, vertical: space.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: context.radii.mdAll,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(AppIcons.mapPin, size: space.lg, color: colors.textSecondary),
                SizedBox(width: space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: context.text.caption
                            .copyWith(color: colors.textMuted),
                      ),
                      SizedBox(height: space.xs),
                      Text(
                        hasValue ? cityArName(cityKey!) : 'اختر المدينة',
                        style: context.text.bodyStrong.copyWith(
                          color:
                              hasValue ? colors.textPrimary : colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(AppIcons.chevronLeft, size: space.lg, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Open the canonical-city picker as a modal bottom sheet; resolves to the
/// chosen city key, or null if dismissed.
Future<String?> showAppCityPicker(
  BuildContext context, {
  String? selected,
  String title = 'اختر المدينة',
  String? excludeKey,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(context.radii.lg)),
    ),
    builder: (sheetContext) => AppCityPickerSheet(
      selected: selected,
      title: title,
      excludeKey: excludeKey,
      onSelect: (key) => Navigator.of(sheetContext).pop(key),
    ),
  );
}

/// The scrollable list of canonical cities shown inside the picker. Exposed so
/// golden tests can render it directly (the modal itself isn't golden-able).
class AppCityPickerSheet extends StatelessWidget {
  const AppCityPickerSheet({
    super.key,
    required this.selected,
    required this.onSelect,
    this.title = 'اختر المدينة',
    this.excludeKey,
  });

  final String? selected;
  final ValueChanged<String> onSelect;
  final String title;
  final String? excludeKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(space.lg, space.lg, space.lg, space.sm),
            child: Row(
              children: [
                Text(
                  title,
                  style:
                      context.text.title.copyWith(color: colors.textPrimary),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(AppIcons.close, color: colors.textMuted),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: space.lg),
              itemCount: kIraqiCities.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: colors.border),
              itemBuilder: (context, i) {
                final city = kIraqiCities[i];
                return _CityRow(
                  city: city,
                  selected: city.key == selected,
                  disabled: city.key == excludeKey,
                  onTap: () => onSelect(city.key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.city,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final IraqiCity city;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final fg = disabled
        ? colors.textMuted
        : (selected ? colors.primary : colors.textPrimary);
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: space.lg, vertical: space.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  city.ar,
                  style: context.text.body.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(AppIcons.check, size: space.lg, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
