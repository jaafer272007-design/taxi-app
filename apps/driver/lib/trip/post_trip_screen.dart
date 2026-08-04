import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'my_trips_controller.dart';
import 'post_trip_controller.dart';
import 'driver_trip_models.dart';

/// Post-a-trip form (APPROVED drivers only): corridor + departure (now/scheduled)
/// + seat count (capped at the vehicle) + the price per seat the DRIVER sets,
/// prefilled with the corridor's suggestion and bounded by its allowed range.
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
      ..setTripType(TripType.general)
      // Back to the suggestion, so the next post starts from a known-good
      // price rather than inheriting the last one silently.
      ..useSuggestedPrice();
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
          _PriceCard(controller: c),
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

/// The price the DRIVER sets, and what a full car pays at it.
///
/// Three decisions worth naming:
///
/// * The suggestion and the allowed range are **always visible**, not only
///   after a mistake. The driver is being asked to name a number on a route
///   they may not run often; the answer belongs next to the question.
/// * The range error appears on **blur or submit, never per keystroke** —
///   flagging "out of range" while they have typed the `1` of `12000` teaches
///   them to distrust the field. The "if it fills" total DOES update live,
///   because showing consequences is feedback, not judgement.
/// * When the price is unusable the total is **withheld**, not computed anyway.
///   A confident number derived from a value the server will reject is worse
///   than no number.
///
/// The input keeps WESTERN digits (the locked rule — the keyboard emits them);
/// every number around it is Arabic-Indic.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.controller});

  final PostTripController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = context.colors;
    final space = context.space;
    final corridor = c.matchedCorridor!;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.cash, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Text('سعر المقعد',
                  style: context.text.bodyStrong
                      .copyWith(color: colors.textPrimary)),
              const Spacer(),
              Text('أنت تحدده',
                  style:
                      context.text.caption.copyWith(color: colors.textMuted)),
            ],
          ),
          SizedBox(height: space.md),
          _PriceField(controller: c),
          SizedBox(height: space.sm),
          _PriceGuidance(
            suggested: corridor.suggestedPricePerSeat,
            min: corridor.minPricePerSeat,
            max: corridor.maxPricePerSeat,
          ),
          if (c.canUseSuggestedPrice) ...[
            SizedBox(height: space.sm),
            _UseSuggestedButton(
              suggested: corridor.suggestedPricePerSeat,
              onTap: c.useSuggestedPrice,
            ),
          ],
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          _FullCarRow(seatCount: c.seatCount, total: c.fullCarTotal),
        ],
      ),
    );
  }
}

/// The price input itself. Stateful only to own the [TextEditingController];
/// the value lives in [PostTripController].
class _PriceField extends StatefulWidget {
  const _PriceField({required this.controller});

  final PostTripController controller;

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.priceInput);
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  void _onFocusChange() {
    // Leaving the field is the moment it becomes fair to point out a problem.
    if (!_focus.hasFocus) widget.controller.markPriceTouched();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    // The controller re-prefills the price when the route changes (and on the
    // "use the usual price" tap). Push that back into the field WITHOUT
    // clobbering what the driver is mid-way through typing.
    if (_text.text != c.priceInput) {
      _text.value = TextEditingValue(
        text: c.priceInput,
        selection: TextSelection.collapsed(offset: c.priceInput.length),
      );
    }

    return AppTextField(
      label: 'المبلغ بالدينار',
      controller: _text,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      // Digits only: an IQD price has no fractions and no separators. This is
      // also what keeps the field WESTERN — the locked input rule.
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 7, // 9,999,999 IQD — far past any real fare, stops paste-bombs
      onChanged: c.setPriceInput,
      onSubmitted: (_) => c.markPriceTouched(),
      error: c.priceError,
    );
  }
}

/// The suggestion and the allowed band, always on screen.
class _PriceGuidance extends StatelessWidget {
  const _PriceGuidance({
    required this.suggested,
    required this.min,
    required this.max,
  });

  final int suggested;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final style =
        context.text.caption.copyWith(color: context.colors.textSecondary);
    return Text(
      min == max
          ? 'السعر على هذا المسار ثابت: ${formatPrice(min)}'
          : 'المعتاد على هذا المسار: ${formatIqd(suggested)}'
              ' · المسموح: ${formatIqd(min)} – ${formatPrice(max)}',
      style: style,
    );
  }
}

/// One tap back to the admin's suggestion — the safe choice, made cheap.
class _UseSuggestedButton extends StatelessWidget {
  const _UseSuggestedButton({required this.suggested, required this.onTap});

  final int suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.pillAll,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: space.md,
          vertical: space.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.check, size: 16, color: colors.primary),
            SizedBox(width: space.xs),
            Text(
              'استخدم السعر المعتاد ${formatPrice(suggested)}',
              style: context.text.caption.copyWith(color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The potential take. The driver is choosing how many seats to offer, so the
/// number that decides it is what a full car pays — not the per-seat price they
/// just typed. "إذا امتلأت" because it is a ceiling, not a promise.
class _FullCarRow extends StatelessWidget {
  const _FullCarRow({required this.seatCount, required this.total});

  final int seatCount;

  /// Null while the price is unusable — then no total is shown at all.
  final int? total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = total;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('إذا امتلأت · ${formatSeats(seatCount)}',
            style: context.text.body.copyWith(color: colors.textSecondary)),
        const Spacer(),
        if (value == null)
          Text('—',
              style: context.text.h1.tabular.copyWith(color: colors.textMuted))
        else
          Text(formatPrice(value),
              style: context.text.h1.tabular.copyWith(color: colors.primary)),
      ],
    );
  }
}
