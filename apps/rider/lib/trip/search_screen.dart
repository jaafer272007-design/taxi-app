import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'results_screen.dart';
import 'trip_format.dart';
import 'trip_models.dart';
import 'trip_search_controller.dart';
import 'widgets/trip_state_views.dart';

/// Trip search form: corridor (with swap), date, optional time window, and
/// "ابحث". This is the authenticated home.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TripSearchController>().ensureCorridorsLoaded();
    });
  }

  Future<void> _pickDate(TripSearchController c) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: c.date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) c.setDate(picked);
  }

  Future<void> _pickTimeWindow(TripSearchController c) async {
    final from = await showTimePicker(
      context: context,
      initialTime: c.fromTime ?? const TimeOfDay(hour: 6, minute: 0),
      helpText: 'من',
    );
    if (from == null || !mounted) return;
    final to = await showTimePicker(
      context: context,
      initialTime: c.toTime ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'إلى',
    );
    if (to == null) return;
    c.setTimeWindow(from, to);
  }

  void _onSearch(TripSearchController c) {
    c.search();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ResultsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TripSearchController>();
    final space = context.space;

    return AppScaffold(
      title: 'ابحث عن رحلة',
      scrollable: true,
      body: _body(context, c, space),
    );
  }

  Widget _body(BuildContext context, TripSearchController c, AppSpacing space) {
    if (c.corridorsLoading) {
      return Padding(
        padding: EdgeInsets.only(top: space.xl4),
        child: Center(
          child: CircularProgressIndicator(color: context.colors.primary),
        ),
      );
    }
    if (c.corridorsError != null) {
      return Padding(
        padding: EdgeInsets.only(top: space.xl4),
        child: TripErrorView(
          message: c.corridorsError!,
          onRetry: () => c.ensureCorridorsLoaded(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: space.md),
        _RoutePicker(controller: c),
        SizedBox(height: space.xl),
        Text('متى؟', style: context.text.label.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: space.sm),
        Row(
          children: [
            Expanded(
              child: _FilterChip(
                icon: AppIcons.calendar,
                label: c.date == null ? 'اليوم' : formatDayShort(c.date!),
                onTap: () => _pickDate(c),
              ),
            ),
            SizedBox(width: space.sm),
            Expanded(
              child: _FilterChip(
                icon: AppIcons.clock,
                label: c.hasTimeWindow
                    ? '${_hm(c.fromTime!)} - ${_hm(c.toTime!)}'
                    : 'أي وقت',
                onTap: () => _pickTimeWindow(c),
                onClear: c.hasTimeWindow ? () => c.clearTimeWindow() : null,
              ),
            ),
          ],
        ),
        SizedBox(height: space.xl),
        Text('نوع الرحلة',
            style: context.text.label.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: space.sm),
        AppSegmentedControl<TripType?>(
          value: c.tripType,
          segments: const <AppSegment<TripType?>>[
            AppSegment(value: null, label: 'الكل'),
            AppSegment(value: TripType.general, label: 'عامة'),
            AppSegment(value: TripType.womenFamily, label: 'نسائية-عائلية'),
          ],
          onChanged: c.setTripType,
        ),
        SizedBox(height: space.xl),
        Text('جنس السائق',
            style: context.text.label.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: space.sm),
        AppSegmentedControl<Gender?>(
          value: c.driverGender,
          segments: const <AppSegment<Gender?>>[
            AppSegment(value: null, label: 'الكل'),
            AppSegment(value: Gender.male, label: 'رجل'),
            AppSegment(value: Gender.female, label: 'امرأة'),
          ],
          onChanged: c.setDriverGender,
        ),
        SizedBox(height: space.xs),
        Text('السائقات قليلات على هذا المسار حالياً.',
            style: context.text.caption.copyWith(color: context.colors.textMuted)),
        SizedBox(height: space.xl2),
        AppButton(
          label: 'ابحث',
          icon: AppIcons.search,
          onPressed: c.canSearch ? () => _onSearch(c) : null,
        ),
      ],
    );
  }

  static String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// From/to city pickers (chosen from the full 18-city list) with a swap control.
/// A city pair is only searchable once the admin has created a corridor for it.
class _RoutePicker extends StatelessWidget {
  const _RoutePicker({required this.controller});

  final TripSearchController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final space = context.space;
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              AppCityField(
                label: 'من',
                cityKey: c.origin,
                onChanged: c.setOrigin,
                excludeKey: c.dest,
              ),
              SizedBox(height: space.sm),
              AppCityField(
                label: 'إلى',
                cityKey: c.dest,
                onChanged: c.setDest,
                excludeKey: c.origin,
              ),
            ],
          ),
        ),
        SizedBox(width: space.sm),
        _SwapButton(onTap: c.swapCities),
      ],
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Semantics(
      button: true,
      label: 'اعكس الاتجاه',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: space.xl4,
          height: space.xl4,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(AppIcons.swap, color: colors.primary, size: space.xl),
        ),
      ),
    );
  }
}

/// A tappable filter pill (date / time window), token-styled.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: space.md, vertical: space.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: context.radii.mdAll,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: space.lg, color: colors.textSecondary),
            SizedBox(width: space.sm),
            Expanded(
              child: Text(
                label,
                style: context.text.body.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: Icon(AppIcons.close, size: space.lg, color: colors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
