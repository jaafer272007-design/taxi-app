import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../trip/trip_format.dart';
import 'booking_models.dart';
import 'my_bookings_controller.dart';

/// "حجوزاتي": the rider's bookings, grouped upcoming/past, each with a status
/// pill. Upcoming CONFIRMED bookings can be cancelled (with a confirm dialog;
/// the backend enforces the free-cancel cutoff and its error is surfaced).
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<MyBookingsController>();
      if (!c.hasLoaded) c.load();
    });
  }

  Future<void> _onCancel(MyBookingsController c, Booking booking) async {
    final confirmed = await _confirmCancelDialog(context);
    if (confirmed != true) return;
    if (!mounted) return;
    final err = await c.cancel(booking.id);
    if (err == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MyBookingsController>();

    return AppScaffold(
      title: 'حجوزاتي',
      padded: false,
      body: switch (c.status) {
        MyBookingsStatus.loading => Center(
            child: CircularProgressIndicator(color: context.colors.primary),
          ),
        MyBookingsStatus.error => _ErrorView(
            message: c.error ?? 'حدث خطأ. حاول مرة أخرى.',
            onRetry: c.load,
          ),
        MyBookingsStatus.loaded =>
          c.isEmpty ? const _EmptyView() : _BookingsList(controller: c, onCancel: _onCancel),
      },
    );
  }
}

class _BookingsList extends StatelessWidget {
  const _BookingsList({required this.controller, required this.onCancel});

  final MyBookingsController controller;
  final Future<void> Function(MyBookingsController, Booking) onCancel;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final upcoming = controller.upcoming;
    final past = controller.past;

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: controller.load,
      child: ListView(
        padding: EdgeInsets.all(space.lg),
        children: [
          if (upcoming.isNotEmpty) ...[
            const _SectionHeader(title: 'رحلات قادمة'),
            SizedBox(height: space.md),
            for (final b in upcoming) ...[
              _BookingCard(
                booking: b,
                cancelling: controller.isCancelling(b.id),
                onCancel: controller.canCancel(b)
                    ? () => onCancel(controller, b)
                    : null,
              ),
              SizedBox(height: space.md),
            ],
          ],
          if (past.isNotEmpty) ...[
            SizedBox(height: space.sm),
            const _SectionHeader(title: 'رحلات سابقة'),
            SizedBox(height: space.md),
            for (final b in past) ...[
              _BookingCard(booking: b, cancelling: false, onCancel: null),
              SizedBox(height: space.md),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: context.text.h2.copyWith(color: context.colors.textPrimary),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.cancelling,
    this.onCancel,
  });

  final Booking booking;
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final trip = booking.trip;
    final corridor = trip?.corridor;
    final route = corridor == null
        ? 'رحلة'
        : '${cityAr(corridor.originCity)} إلى ${cityAr(corridor.destCity)}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  route,
                  style: context.text.title.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: space.sm),
              _statusPill(booking.status),
            ],
          ),
          if (trip != null) ...[
            SizedBox(height: space.md),
            Row(
              children: [
                Icon(AppIcons.clock, size: space.lg, color: colors.textMuted),
                SizedBox(width: space.sm),
                Text(
                  formatTime(trip.departureTime),
                  style: context.text.body.tabular
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ],
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            children: [
              Icon(AppIcons.seat, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Text('${booking.seatCount} مقعد',
                  style:
                      context.text.body.copyWith(color: colors.textSecondary)),
              const Spacer(),
              Text(
                formatPrice(booking.fare),
                style: context.text.title.tabular.copyWith(color: colors.primary),
              ),
            ],
          ),
          if (onCancel != null) ...[
            SizedBox(height: space.md),
            AppButton(
              label: 'إلغاء الحجز',
              variant: AppButtonVariant.danger,
              icon: AppIcons.close,
              loading: cancelling,
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

Widget _statusPill(BookingStatus status) {
  final (String label, AppBadgeTone tone, IconData icon) = switch (status) {
    BookingStatus.confirmed => ('مؤكد', AppBadgeTone.success, AppIcons.success),
    BookingStatus.onboard => ('على متن الرحلة', AppBadgeTone.info, AppIcons.car),
    BookingStatus.completed => ('مكتملة', AppBadgeTone.neutral, AppIcons.check),
    BookingStatus.cancelled => ('ملغاة', AppBadgeTone.danger, AppIcons.close),
    BookingStatus.noShow => ('لم تحضر', AppBadgeTone.warning, AppIcons.warning),
    BookingStatus.unknown => ('—', AppBadgeTone.neutral, AppIcons.info),
  };
  return AppPill(label: label, tone: tone, icon: icon);
}

Future<bool?> _confirmCancelDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final space = ctx.space;
      final colors = ctx.colors;
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: ctx.radii.lgAll),
        child: Padding(
          padding: EdgeInsets.all(space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إلغاء الحجز',
                  style: ctx.text.h2.copyWith(color: colors.textPrimary)),
              SizedBox(height: space.sm),
              Text(
                'هل تريد إلغاء هذا الحجز؟ الإلغاء المجاني متاح حتى 15 دقيقة قبل المغادرة.',
                style: ctx.text.body.copyWith(color: colors.textSecondary),
              ),
              SizedBox(height: space.lg),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'تراجع',
                      variant: AppButtonVariant.ghost,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  SizedBox(width: space.sm),
                  Expanded(
                    child: AppButton(
                      label: 'نعم، إلغاء',
                      variant: AppButtonVariant.danger,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2,
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.seat, color: colors.primary, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text('لا توجد حجوزات بعد',
                style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.sm),
            Text('ابحث عن رحلة واحجز مقعدك الأول.',
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2,
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text(message,
                style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.xl),
            AppButton(
              label: 'إعادة المحاولة',
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
