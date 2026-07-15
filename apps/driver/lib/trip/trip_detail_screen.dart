import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'driver_trip_models.dart';
import 'rate_rider_sheet.dart';
import 'trip_detail_controller.dart';
import 'trip_format.dart';

/// Driver's view of ONE of their trips: the trip's info, the list of bookings
/// (rider name, seats, pickup/dropoff, status) and every lifecycle action —
/// start, per-rider onboard / no-show, complete (with a cash summary), cancel,
/// and post-completion rider rating.
class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<TripDetailController>();
      if (!c.hasLoaded) c.load();
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    AppButtonVariant confirmVariant = AppButtonVariant.primary,
  }) async {
    final colors = context.colors;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(title,
            style: ctx.text.title.copyWith(color: colors.textPrimary)),
        content: Text(message,
            style: ctx.text.body.copyWith(color: colors.textSecondary)),
        actions: [
          AppButton(
            label: 'تراجع',
            variant: AppButtonVariant.ghost,
            expand: false,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: confirmLabel,
            variant: confirmVariant,
            expand: false,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _onStart(TripDetailController c) async {
    final ok = await _confirm(
      title: 'ابدأ الرحلة؟',
      message: 'سيتحوّل وضع الرحلة إلى «جارية» ولن يعود بالإمكان الحجز عليها.',
      confirmLabel: 'ابدأ الرحلة',
    );
    if (!ok) return;
    final err = await c.start();
    if (!mounted) return;
    if (err != null) _snack(err);
  }

  Future<void> _onComplete(TripDetailController c) async {
    final ok = await _confirm(
      title: 'أنهِ الرحلة؟',
      message: 'سيتم تحصيل الأجرة نقداً من الركاب الذين صعدوا وإنهاء الرحلة.',
      confirmLabel: 'أنهِ الرحلة',
    );
    if (!ok) return;
    final err = await c.complete();
    if (!mounted) return;
    if (err != null) _snack(err);
  }

  Future<void> _onCancel(TripDetailController c) async {
    final ok = await _confirm(
      title: 'إلغاء الرحلة؟',
      message: 'سيتم إلغاء جميع الحجوزات المؤكدة وإشعار الركاب.',
      confirmLabel: 'إلغاء الرحلة',
      confirmVariant: AppButtonVariant.danger,
    );
    if (!ok) return;
    final err = await c.cancel();
    if (!mounted) return;
    if (err != null) _snack(err);
  }

  Future<void> _onBookingAction(
      TripDetailController c, Future<String?> Function() action) async {
    final err = await action();
    if (!mounted) return;
    if (err != null) _snack(err);
  }

  Future<void> _onRate(TripDetailController c, TripBooking b) async {
    await showRateRiderSheet(
      context,
      riderName: b.riderName ?? 'راكب',
      onSubmit: (score, comment) =>
          c.rateRider(riderId: b.riderId, score: score, comment: comment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TripDetailController>();
    final space = context.space;
    final route = _routeLabel(c);

    return AppScaffold(
      title: 'تفاصيل الرحلة',
      padded: false,
      bottomBar: _bottomBar(c),
      body: ListView(
        padding: EdgeInsets.all(space.lg),
        children: [
          _TripInfoCard(controller: c, route: route),
          if (c.summary != null) ...[
            SizedBox(height: space.md),
            _SummaryCard(summary: c.summary!),
          ],
          SizedBox(height: space.lg),
          Text('الحجوزات',
              style: context.text.h2.copyWith(color: context.colors.textPrimary)),
          SizedBox(height: space.md),
          _bookingsSection(c),
        ],
      ),
    );
  }

  Widget _bookingsSection(TripDetailController c) {
    final space = context.space;
    switch (c.loadStatus) {
      case TripDetailStatus.loading:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: space.xl2),
          child: Center(
              child: CircularProgressIndicator(color: context.colors.primary)),
        );
      case TripDetailStatus.error:
        return _InlineError(message: c.error ?? 'حدث خطأ.', onRetry: c.load);
      case TripDetailStatus.loaded:
        if (c.isEmpty) return const _NoBookings();
        return Column(
          children: [
            for (final b in c.bookings) ...[
              _BookingCard(
                controller: c,
                booking: b,
                onOnboard: () =>
                    _onBookingAction(c, () => c.onboard(b.id)),
                onNoShow: () => _onBookingAction(c, () => c.noShow(b.id)),
                onRate: () => _onRate(c, b),
              ),
              SizedBox(height: space.md),
            ],
          ],
        );
    }
  }

  Widget? _bottomBar(TripDetailController c) {
    if (c.canStart) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'ابدأ الرحلة',
            icon: AppIcons.car,
            loading: c.tripActionInFlight,
            onPressed: () => _onStart(c),
          ),
          SizedBox(height: context.space.sm),
          AppButton(
            label: 'إلغاء الرحلة',
            icon: AppIcons.close,
            variant: AppButtonVariant.dangerTonal,
            onPressed: c.tripActionInFlight ? null : () => _onCancel(c),
          ),
        ],
      );
    }
    if (c.isEnRoute) {
      return AppButton(
        label: 'أنهِ الرحلة',
        icon: AppIcons.check,
        loading: c.tripActionInFlight,
        onPressed: () => _onComplete(c),
      );
    }
    return null;
  }

  String _routeLabel(TripDetailController c) {
    final corridor = c.corridor;
    if (corridor == null) return 'رحلة';
    return '${cityAr(corridor.originCity)} إلى ${cityAr(corridor.destCity)}';
  }
}

class _TripInfoCard extends StatelessWidget {
  const _TripInfoCard({required this.controller, required this.route});

  final TripDetailController controller;
  final String route;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final trip = controller.trip;
    final typeBadge = tripTypeBadge(trip.tripType);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(route,
                    style: context.text.title.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(width: space.sm),
              tripStatusPill(trip.status),
            ],
          ),
          if (typeBadge != null) ...[
            SizedBox(height: space.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: typeBadge,
            ),
          ],
          SizedBox(height: space.md),
          Row(
            children: [
              _MetaChip(
                  icon: AppIcons.clock, label: formatTime(trip.departureTime)),
              SizedBox(width: space.lg),
              _MetaChip(
                  icon: AppIcons.calendar,
                  label: formatDayBaghdad(trip.departureTime)),
            ],
          ),
          SizedBox(height: space.sm),
          Row(
            children: [
              _MetaChip(
                icon: AppIcons.seat,
                label: '${trip.seatsBooked}/${trip.seatsTotal} محجوز',
              ),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            children: [
              Text(formatPrice(trip.pricePerSeat),
                  style: context.text.title.tabular.copyWith(color: colors.primary)),
              Text(' / للمقعد',
                  style: context.text.caption.copyWith(color: colors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final TripCompletionSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.success, size: space.xl, color: colors.success),
              SizedBox(width: space.sm),
              Text('اكتملت الرحلة',
                  style: context.text.title.copyWith(color: colors.textPrimary)),
            ],
          ),
          SizedBox(height: space.md),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: 'مقاعد ركبت',
                  value: '${summary.seatsRidden}',
                ),
              ),
              Expanded(
                child: _SummaryStat(
                  label: 'نقد محصّل',
                  value: formatPrice(summary.cashCollected),
                  highlight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.caption.copyWith(color: colors.textMuted)),
        SizedBox(height: space.xs),
        Text(value,
            style: context.text.h2.tabular.copyWith(
                color: highlight ? colors.primary : colors.textPrimary)),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: space.lg, color: colors.textMuted),
        SizedBox(width: space.sm),
        Text(label,
            style: context.text.body.tabular.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.controller,
    required this.booking,
    required this.onOnboard,
    required this.onNoShow,
    required this.onRate,
  });

  final TripDetailController controller;
  final TripBooking booking;
  final VoidCallback onOnboard;
  final VoidCallback onNoShow;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final name = booking.riderName ?? 'راكب';
    final inFlight = controller.bookingActionInFlight(booking.id);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: name, size: space.xl2),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: context.text.bodyStrong
                            .copyWith(color: colors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: space.xs),
                    Text('${booking.seatCount} مقعد · ${formatPrice(booking.fare)}',
                        style: context.text.caption
                            .copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: space.sm),
              bookingStatusPill(booking.status),
            ],
          ),
          SizedBox(height: space.md),
          _PointRow(icon: AppIcons.mapPin, label: 'من: ${booking.pickupLabel}'),
          SizedBox(height: space.xs),
          _PointRow(icon: AppIcons.route, label: 'إلى: ${booking.dropoffLabel}'),
          if (controller.canTransition(booking)) ...[
            SizedBox(height: space.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'صعد',
                    icon: AppIcons.check,
                    size: AppButtonSize.small,
                    loading: inFlight,
                    onPressed: onOnboard,
                  ),
                ),
                SizedBox(width: space.sm),
                Expanded(
                  child: AppButton(
                    label: 'لم يحضر',
                    icon: AppIcons.close,
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.dangerTonal,
                    onPressed: inFlight ? null : onNoShow,
                  ),
                ),
              ],
            ),
          ],
          if (controller.isDone &&
              booking.status == BookingStatus.completed) ...[
            SizedBox(height: space.md),
            if (controller.isRated(booking.riderId))
              Row(
                children: [
                  Icon(AppIcons.success, size: space.lg, color: colors.success),
                  SizedBox(width: space.sm),
                  Text('تم التقييم',
                      style: context.text.label.copyWith(color: colors.success)),
                ],
              )
            else
              AppButton(
                label: 'قيّم الراكب',
                icon: AppIcons.star,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                expand: false,
                onPressed: onRate,
              ),
          ],
        ],
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: space.lg, color: colors.textMuted),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(label,
              style: context.text.body.copyWith(color: colors.textSecondary)),
        ),
      ],
    );
  }
}

class _NoBookings extends StatelessWidget {
  const _NoBookings();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space.xl2),
      child: Column(
        children: [
          Icon(AppIcons.users, size: space.xl3, color: colors.textMuted),
          SizedBox(height: space.md),
          Text('لا توجد حجوزات على هذه الرحلة بعد',
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space.xl),
      child: Column(
        children: [
          Icon(AppIcons.warning, size: space.xl2, color: colors.danger),
          SizedBox(height: space.md),
          Text(message,
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center),
          SizedBox(height: space.lg),
          AppButton(label: 'إعادة المحاولة', expand: false, onPressed: onRetry),
        ],
      ),
    );
  }
}

/// Status pill for a trip (shared with the trips list mapping).
Widget tripStatusPill(TripStatus status) {
  final (String label, AppBadgeTone tone) = switch (status) {
    TripStatus.open => ('مفتوحة', AppBadgeTone.success),
    TripStatus.locked => ('مكتملة الحجز', AppBadgeTone.warning),
    TripStatus.enRoute => ('جارية', AppBadgeTone.info),
    TripStatus.completed || TripStatus.settled => ('منتهية', AppBadgeTone.neutral),
    TripStatus.cancelled => ('ملغاة', AppBadgeTone.danger),
    TripStatus.unknown => ('—', AppBadgeTone.neutral),
  };
  return AppPill(label: label, tone: tone);
}

/// Badge marking a women/family trip; `null` for general trips (no badge).
Widget? tripTypeBadge(TripType type) => type == TripType.womenFamily
    ? const AppPill(
        label: 'نسائية/عائلية',
        tone: AppBadgeTone.info,
        icon: AppIcons.users,
      )
    : null;

/// Status pill for a single booking.
Widget bookingStatusPill(BookingStatus status) {
  final (String label, AppBadgeTone tone, IconData? icon) = switch (status) {
    BookingStatus.confirmed => ('مؤكد', AppBadgeTone.info, null),
    BookingStatus.onboard => ('صعد', AppBadgeTone.success, AppIcons.check),
    BookingStatus.completed => ('مكتمل', AppBadgeTone.success, AppIcons.success),
    BookingStatus.noShow => ('لم يحضر', AppBadgeTone.danger, AppIcons.close),
    BookingStatus.cancelled => ('ملغى', AppBadgeTone.neutral, AppIcons.close),
    BookingStatus.unknown => ('—', AppBadgeTone.neutral, null),
  };
  return AppPill(label: label, tone: tone, icon: icon);
}
