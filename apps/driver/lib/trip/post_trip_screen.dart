import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'my_trips_controller.dart';
import 'post_trip_controller.dart';
import 'driver_trip_models.dart';

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
        const _SectionLabel('نوع الرحلة'),
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
        const _SectionLabel('متى؟'),
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
        const _SectionLabel('كم مقعداً تعرض؟'),
        SizedBox(height: space.sm),
        SeatCountPicker(
          value: c.seatCount,
          max: c.maxSeats,
          // Always draw at least four tiles so the vehicle's ceiling is visible
          // as dead tiles rather than as a `+` that silently stops working.
          offered: c.maxSeats < 4 ? 4 : c.maxSeats,
          onChanged: c.setSeatCount,
          hint: 'سعة سيارتك ${formatSeats(c.maxSeats)}',
        ),
        if (c.matchedCorridor != null) ...[
          SizedBox(height: space.xl),
          _PriceCard(pricePerSeat: c.pricePerSeat, seatCount: c.seatCount),
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
    // One card: rail + both endpoints + swap, per the hand-off.
    return RouteSearchCard(
      origin: c.origin,
      dest: c.dest,
      onOriginChanged: c.setOrigin,
      onDestChanged: c.setDest,
      onSwap: c.swapCities,
    );
  }
}


class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: context.text.label.copyWith(color: context.colors.textSecondary),
      );
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: space.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Opaque tonal, not `primary` at 12%: the toggle sits on the page
              // background here but on a card in other layouts, and an alpha
              // tint measures differently on each.
              color: selected ? colors.primaryTonal : colors.surface,
              borderRadius: context.radii.fieldLgAll,
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: selected ? 2 : 1,
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
    return Semantics(
      button: true,
      label: 'موعد الانطلاق',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: space.lg, vertical: space.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: context.radii.fieldLgAll,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(AppIcons.calendar,
                    size: space.lg, color: colors.textSecondary),
                SizedBox(width: space.sm),
                Expanded(
                  child: Text(
                    label,
                    style: context.text.body.copyWith(color: colors.textPrimary),
                  ),
                ),
                Icon(AppIcons.chevronLeft,
                    size: space.lg, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Display time — Arabic-Indic, via the shared helper. The DateTime here is
  // already local wall-clock (it came from the picker), so no Baghdad shift.
  static String _hm(DateTime t) => formatClock(t.hour, t.minute);
}

/// What the trip is worth: the system-set seat price, and what a full car pays.
///
/// The driver is choosing how many seats to offer, so the number that decides
/// that choice is the *potential take* — showing only the per-seat price makes
/// them do the arithmetic themselves. It is labelled "إذا امتلأت" rather than
/// stated flatly, because it is a ceiling, not a promise.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.pricePerSeat, required this.seatCount});

  final int pricePerSeat;
  final int seatCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Icon(AppIcons.cash, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('السعر للمقعد',
                        style: context.text.bodyStrong
                            .copyWith(color: colors.textPrimary)),
                    Text('يحدده النظام',
                        style: context.text.caption
                            .copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              Text(formatPrice(pricePerSeat),
                  style: context.text.title.tabular
                      .copyWith(color: colors.textPrimary)),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('إذا امتلأت · ${formatSeats(seatCount)}',
                  style:
                      context.text.body.copyWith(color: colors.textSecondary)),
              const Spacer(),
              Text(formatPrice(pricePerSeat * seatCount),
                  style:
                      context.text.h1.tabular.copyWith(color: colors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}
