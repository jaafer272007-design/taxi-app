import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../trip/trip_format.dart';
import 'booking_confirmation_screen.dart';
import 'booking_controller.dart';
import 'booking_error.dart';

/// Reserve-a-seat form: seat count + live fare, door-to-door pickup/dropoff, a
/// cash note, and a confirm button. Reads/writes a [BookingController] provided
/// by the route that opened this screen.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late final TextEditingController _pickupCtrl;
  late final TextEditingController _dropoffCtrl;

  @override
  void initState() {
    super.initState();
    final c = context.read<BookingController>();
    _pickupCtrl = TextEditingController(text: c.pickup.label);
    _dropoffCtrl = TextEditingController(text: c.dropoff.label);
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final c = context.read<BookingController>();
    final ok = await c.submit();
    if (!ok) return;
    if (!mounted) return;
    final result = c.result!;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BookingConfirmationScreen(
          seatCount: result.seatCount,
          fare: result.fare,
          departureTime: c.trip.departureTime,
          originCity: c.originCity,
          destCity: c.destCity,
        ),
      ),
    );
  }

  String _pointLabel(String base, String? city) =>
      city == null ? base : '$base في ${cityAr(city)}';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BookingController>();
    final space = context.space;
    final error = c.error;
    final seatGone = error?.kind == BookingErrorKind.seatGone;

    return AppScaffold(
      title: 'حجز مقعد',
      scrollable: true,
      bottomBar: AppButton(
        label: 'تأكيد الحجز',
        icon: AppIcons.check,
        loading: c.submitting,
        onPressed: (c.canSubmit && !seatGone) ? _confirm : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.md),
          _TripSummaryCard(controller: c),
          SizedBox(height: space.lg),
          _SeatSection(controller: c),
          SizedBox(height: space.lg),
          _FareRow(fare: c.fare),
          SizedBox(height: space.xl),
          AppTextField(
            label: _pointLabel('نقطة الانطلاق', c.originCity),
            hint: 'مثال: حي السلام، قرب الجامع',
            prefixIcon: AppIcons.mapPin,
            controller: _pickupCtrl,
            textInputAction: TextInputAction.next,
            onChanged: c.setPickupLabel,
          ),
          SizedBox(height: space.lg),
          AppTextField(
            label: _pointLabel('نقطة النزول', c.destCity),
            hint: 'مثال: قرب المستشفى التعليمي',
            prefixIcon: AppIcons.mapPin,
            controller: _dropoffCtrl,
            textInputAction: TextInputAction.done,
            onChanged: c.setDropoffLabel,
          ),
          SizedBox(height: space.lg),
          const _CashNote(),
          if (error != null) ...[
            SizedBox(height: space.lg),
            _ErrorBanner(
              error: error,
              onBack: seatGone ? () => Navigator.of(context).pop() : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact recap of the trip being booked: driver + time + price per seat.
class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final trip = controller.trip;
    final name = (trip.driverName?.trim().isNotEmpty ?? false)
        ? trip.driverName!.trim()
        : 'سائق';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: name),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: context.text.title, maxLines: 1),
                    SizedBox(height: space.xs),
                    RatingStars(value: trip.driverRatingAvg, size: space.lg),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('وقت الانطلاق',
                      style: context.text.caption
                          .copyWith(color: colors.textMuted)),
                  SizedBox(height: space.xs),
                  Text(formatTime(trip.departureTime),
                      style: context.text.h2.tabular
                          .copyWith(color: colors.textPrimary)),
                ],
              ),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            children: [
              Icon(AppIcons.cash, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Text('السعر للمقعد',
                  style: context.text.body
                      .copyWith(color: colors.textSecondary)),
              const Spacer(),
              Text(formatPrice(trip.pricePerSeat),
                  style: context.text.bodyStrong.tabular
                      .copyWith(color: colors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Seat-count label + stepper, bounded to 1..min(4, seatsAvailable).
class _SeatSection extends StatelessWidget {
  const _SeatSection({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('عدد المقاعد',
            style: context.text.label.copyWith(color: colors.textSecondary)),
        SizedBox(height: space.sm),
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
        Text('المتاح: ${controller.trip.seatsAvailable} مقاعد',
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

/// Live total fare = price per seat × seats.
class _FareRow extends StatelessWidget {
  const _FareRow({required this.fare});

  final int fare;

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
          Text('الإجمالي',
              style: context.text.bodyStrong.copyWith(color: colors.textPrimary)),
          const Spacer(),
          Text(formatPrice(fare),
              style: context.text.h2.tabular.copyWith(color: colors.primary)),
        ],
      ),
    );
  }
}

/// "الدفع نقداً عند الرحلة" — informational, no action (cash only in Phase 1).
class _CashNote extends StatelessWidget {
  const _CashNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      children: [
        Icon(AppIcons.cash, size: space.lg, color: colors.textSecondary),
        SizedBox(width: space.sm),
        Expanded(
          child: Text('الدفع نقداً عند الرحلة',
              style: context.text.body.copyWith(color: colors.textSecondary)),
        ),
      ],
    );
  }
}

/// Inline error. Seat-gone offers a back-to-results action; everything else
/// just shows the (already-Arabic) message.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, this.onBack});

  final BookingError error;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final seatGone = error.kind == BookingErrorKind.seatGone;
    final tone = seatGone ? colors.warning : colors.danger;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: context.radii.mdAll,
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(seatGone ? AppIcons.warning : AppIcons.danger,
                  size: space.lg, color: tone),
              SizedBox(width: space.sm),
              Expanded(
                child: Text(error.message,
                    style: context.text.body.copyWith(color: colors.textPrimary)),
              ),
            ],
          ),
          if (onBack != null) ...[
            SizedBox(height: space.md),
            AppButton(
              label: 'عد إلى الرحلات',
              variant: AppButtonVariant.secondary,
              icon: AppIcons.back,
              expand: false,
              onPressed: onBack,
            ),
          ],
        ],
      ),
    );
  }
}
