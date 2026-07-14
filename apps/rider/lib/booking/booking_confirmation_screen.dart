import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../trip/trip_format.dart';
import 'booking_api.dart';
import 'my_bookings_controller.dart';
import 'my_bookings_screen.dart';

/// Success screen after a seat is reserved: a confirmation hero, a recap of the
/// trip + seats + total fare, and a path to "حجوزاتي". Takes plain values (not
/// the controller) so it outlives the booking form's provider.
class BookingConfirmationScreen extends StatelessWidget {
  const BookingConfirmationScreen({
    super.key,
    required this.seatCount,
    required this.fare,
    required this.departureTime,
    this.originCity,
    this.destCity,
  });

  final int seatCount;
  final int fare;
  final DateTime departureTime;
  final String? originCity;
  final String? destCity;

  void _openMyBookings(BuildContext context) {
    final api = context.read<BookingApi>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<MyBookingsController>(
          create: (_) => MyBookingsController(api: api),
          child: const MyBookingsScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;

    return AppScaffold(
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'عرض حجوزاتي',
            icon: AppIcons.seat,
            onPressed: () => _openMyBookings(context),
          ),
          SizedBox(height: space.sm),
          AppButton(
            label: 'العودة للرئيسية',
            variant: AppButtonVariant.ghost,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: space.xl2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: space.xl4 + space.xl3, // 72
                  height: space.xl4 + space.xl3,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(AppIcons.success,
                      color: colors.success, size: space.xl3),
                ),
              ),
              SizedBox(height: space.lg),
              Text('تم تأكيد حجزك',
                  style: context.text.h1.copyWith(color: colors.textPrimary),
                  textAlign: TextAlign.center),
              SizedBox(height: space.sm),
              Text('أبلغنا السائق بحجزك. ستصلك الإشعارات بأي تحديث.',
                  style: context.text.body.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center),
              SizedBox(height: space.xl2),
              _SummaryCard(
                seatCount: seatCount,
                fare: fare,
                departureTime: departureTime,
                originCity: originCity,
                destCity: destCity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.seatCount,
    required this.fare,
    required this.departureTime,
    this.originCity,
    this.destCity,
  });

  final int seatCount;
  final int fare;
  final DateTime departureTime;
  final String? originCity;
  final String? destCity;

  @override
  Widget build(BuildContext context) {
    final route = (originCity != null && destCity != null)
        ? '${cityAr(originCity!)} إلى ${cityAr(destCity!)}'
        : null;

    return AppCard(
      child: Column(
        children: [
          if (route != null)
            _Row(icon: AppIcons.route, label: 'المسار', value: route),
          _Row(
            icon: AppIcons.clock,
            label: 'وقت الانطلاق',
            value: formatTime(departureTime),
          ),
          _Row(
            icon: AppIcons.seat,
            label: 'المقاعد',
            value: '$seatCount',
          ),
          _Row(
            icon: AppIcons.cash,
            label: 'الإجمالي (نقداً)',
            value: formatPrice(fare),
            last: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: space.xl, color: colors.textMuted),
            SizedBox(width: space.md),
            Text(label,
                style: context.text.body.copyWith(color: colors.textSecondary)),
            const Spacer(),
            Text(value,
                style: context.text.bodyStrong.tabular
                    .copyWith(color: colors.textPrimary)),
          ],
        ),
        if (!last) ...[
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
        ],
      ],
    );
  }
}
