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
    final corridor = c.corridor;
    if (corridor == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: TripEmptyView(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: space.md),
        _CorridorSelector(corridor: corridor, onSwap: c.swapDirection),
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
        SizedBox(height: space.xl2),
        AppButton(
          label: 'ابحث',
          icon: AppIcons.search,
          onPressed: () => _onSearch(c),
        ),
      ],
    );
  }

  static String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// من … ⇆ … إلى, with a swap control.
class _CorridorSelector extends StatelessWidget {
  const _CorridorSelector({required this.corridor, required this.onSwap});

  final Corridor corridor;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return AppCard(
      child: Row(
        children: [
          Expanded(child: _Endpoint(label: 'من', city: cityAr(corridor.originCity))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: space.sm),
            child: _SwapButton(onTap: onSwap),
          ),
          Expanded(
            child: _Endpoint(
              label: 'إلى',
              city: cityAr(corridor.destCity),
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.label, required this.city, this.alignEnd = false});

  final String label;
  final String city;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.text.caption.copyWith(color: colors.textMuted)),
        SizedBox(height: context.space.xs),
        Text(city, style: context.text.h2.copyWith(color: colors.textPrimary)),
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
