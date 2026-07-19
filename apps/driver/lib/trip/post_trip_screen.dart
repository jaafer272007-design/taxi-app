import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'my_trips_controller.dart';
import 'post_trip_controller.dart';
import 'driver_trip_models.dart';
import 'trip_format.dart';

/// Post-a-trip form (APPROVED drivers only): corridor + departure (now/scheduled)
/// + seat count (capped at the vehicle) + read-only corridor price.
class PostTripScreen extends StatelessWidget {
  const PostTripScreen({super.key, required this.onPosted});

  /// Called after a trip is posted successfully (switch to رحلاتي).
  final VoidCallback onPosted;

  Future<void> _submit(BuildContext context, PostTripController c) async {
    final ok = await c.submit();
    if (!ok) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('تم نشر رحلتك بنجاح.')));
    c
      ..setSeatCount(1)
      ..setMode(DepartMode.now)
      ..setScheduledAt(null)
      ..setTripType(TripType.general);
    context.read<MyTripsController>().load();
    onPosted();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PostTripController>();

    return AppScaffold(
      title: 'انشر رحلة',
      scrollable: true,
      bottomBar: AppButton(
        label: 'انشر الرحلة',
        icon: AppIcons.route,
        loading: c.submitting,
        onPressed: c.canSubmit ? () => _submit(context, c) : null,
      ),
      body: switch (c.corridorsLoad) {
        CorridorsLoad.loading => Padding(
            padding: EdgeInsets.only(top: context.space.xl4),
            child: Center(
                child: CircularProgressIndicator(color: context.colors.primary)),
          ),
        CorridorsLoad.error => Padding(
            padding: EdgeInsets.only(top: context.space.xl3),
            child: Column(
              children: [
                DriverBanner(
                  message: c.corridorsError ?? 'تعذّر تحميل المسارات.',
                  tone: BannerTone.danger,
                ),
                SizedBox(height: context.space.lg),
                AppButton(
                  label: 'إعادة المحاولة',
                  expand: false,
                  onPressed: c.loadCorridors,
                ),
              ],
            ),
          ),
        CorridorsLoad.ready => _Form(controller: c),
      },
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.controller});

  final PostTripController controller;

  Future<void> _pickSchedule(BuildContext context, PostTripController c) async {
    final now = DateTime.now();
    final base = c.scheduledAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null) return;
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    c.setScheduledAt(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final space = context.space;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: space.md),
        _RoutePicker(controller: c),
        if (c.noCorridorForPair) ...[
          SizedBox(height: space.md),
          const DriverBanner(
            message:
                'لا يوجد ممر لهذا المسار حالياً. تواصل مع الأدمن لإضافته قبل نشر الرحلة.',
            tone: BannerTone.warning,
          ),
        ],
        SizedBox(height: space.xl),
        Text('نوع الرحلة',
            style: context.text.label.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: space.sm),
        AppSegmentedControl<TripType>(
          value: c.tripType,
          segments: const [
            AppSegment(value: TripType.general, label: 'عامة'),
            AppSegment(value: TripType.womenFamily, label: 'نسائية-عائلية'),
          ],
          onChanged: c.setTripType,
        ),
        SizedBox(height: space.xs),
        Text(
          c.tripType == TripType.womenFamily
              ? 'كل الركّاب يجب أن يكنّ نساءً، ويمكن للمرأة حجز مقاعد لعائلتها. يمكن لأي سائق نشر هذا النوع.'
              : 'متاحة لجميع الركّاب.',
          style: context.text.caption.copyWith(color: context.colors.textMuted),
        ),
        SizedBox(height: space.xl),
        Text('متى؟',
            style: context.text.label.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: space.sm),
        _ModeToggle(
          mode: c.mode,
          onNow: () => c.setMode(DepartMode.now),
          onScheduled: () => c.setMode(DepartMode.scheduled),
        ),
        if (c.mode == DepartMode.scheduled) ...[
          SizedBox(height: space.md),
          _ScheduleChip(
            at: c.scheduledAt,
            onTap: () => _pickSchedule(context, c),
          ),
        ],
        SizedBox(height: space.xl),
        Text('عدد المقاعد',
            style: context.text.label.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: space.sm),
        _SeatStepper(controller: c),
        if (c.matchedCorridor != null) ...[
          SizedBox(height: space.xl),
          _PriceCard(pricePerSeat: c.pricePerSeat),
        ],
        if (c.error != null) ...[
          SizedBox(height: space.lg),
          DriverBanner(message: c.error!, tone: BannerTone.danger),
        ],
      ],
    );
  }
}

/// From/to city pickers (full 18-city list) with a swap control. A pair is only
/// postable once the admin has created an active corridor for it.
class _RoutePicker extends StatelessWidget {
  const _RoutePicker({required this.controller});

  final PostTripController controller;

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

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.onNow,
    required this.onScheduled,
  });

  final DepartMode mode;
  final VoidCallback onNow;
  final VoidCallback onScheduled;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return Row(
      children: [
        Expanded(
          child: _ToggleOption(
            label: 'الآن',
            icon: AppIcons.clock,
            selected: mode == DepartMode.now,
            onTap: onNow,
          ),
        ),
        SizedBox(width: space.sm),
        Expanded(
          child: _ToggleOption(
            label: 'جدولة',
            icon: AppIcons.calendar,
            selected: mode == DepartMode.scheduled,
            onTap: onScheduled,
          ),
        ),
      ],
    );
  }
}

class _ToggleOption extends StatelessWidget {
  const _ToggleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: space.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surface,
          borderRadius: context.radii.mdAll,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: space.lg,
                color: selected ? colors.primary : colors.textSecondary),
            SizedBox(width: space.sm),
            Text(
              label,
              style: context.text.bodyStrong.copyWith(
                color: selected ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleChip extends StatelessWidget {
  const _ScheduleChip({required this.at, required this.onTap});

  final DateTime? at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final label = at == null
        ? 'اختر التاريخ والوقت'
        : '${formatDayShort(at!)} · ${_hm(at!)}';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: space.lg, vertical: space.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: context.radii.mdAll,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(AppIcons.calendar, size: space.lg, color: colors.textSecondary),
            SizedBox(width: space.sm),
            Expanded(
              child: Text(
                label,
                style: context.text.body.copyWith(color: colors.textPrimary),
              ),
            ),
            Icon(AppIcons.chevronLeft, size: space.lg, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _SeatStepper extends StatelessWidget {
  const _SeatStepper({required this.controller});

  final PostTripController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepButton(
              icon: AppIcons.minus,
              semanticLabel: 'إنقاص',
              onTap: controller.canDecrement ? controller.decrementSeat : null,
            ),
            Expanded(
              child: Center(
                child: Text('${controller.seatCount}',
                    style: context.text.h1.tabular
                        .copyWith(color: colors.textPrimary)),
              ),
            ),
            _StepButton(
              icon: AppIcons.plus,
              semanticLabel: 'زيادة',
              onTap: controller.canIncrement ? controller.incrementSeat : null,
            ),
          ],
        ),
        SizedBox(height: space.xs),
        Text('حتى ${controller.maxSeats} (سعة سيارتك)',
            style: context.text.caption.copyWith(color: colors.textMuted)),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: space.xl4 + space.xs,
            height: space.xl4 + space.xs,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.primary, size: space.xl),
          ),
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.pricePerSeat});

  final int pricePerSeat;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.lg, vertical: space.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: context.radii.mdAll,
      ),
      child: Row(
        children: [
          Icon(AppIcons.cash, size: space.lg, color: colors.textMuted),
          SizedBox(width: space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('السعر للمقعد',
                  style: context.text.bodyStrong.copyWith(color: colors.textPrimary)),
              Text('يحدده النظام',
                  style: context.text.caption.copyWith(color: colors.textMuted)),
            ],
          ),
          const Spacer(),
          Text(formatPrice(pricePerSeat),
              style: context.text.h2.tabular.copyWith(color: colors.primary)),
        ],
      ),
    );
  }
}
