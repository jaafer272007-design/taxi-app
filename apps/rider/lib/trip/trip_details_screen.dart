import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'trip_format.dart';
import 'trip_models.dart';

/// Read-only expanded view of a trip. Booking is the next screen — the
/// "احجز مقعد" button is a disabled placeholder for now.
class TripDetailsScreen extends StatelessWidget {
  const TripDetailsScreen({super.key, required this.trip});

  final TripSummary trip;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final name = (trip.driverName?.trim().isNotEmpty ?? false)
        ? trip.driverName!.trim()
        : 'سائق';

    return AppScaffold(
      title: 'تفاصيل الرحلة',
      scrollable: true,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'الحجز غير متاح بعد',
            style: context.text.caption.copyWith(color: colors.textMuted),
          ),
          SizedBox(height: space.sm),
          const AppButton(label: 'احجز مقعد', onPressed: null),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.md),
          AppCard(
            child: Row(
              children: [
                AppAvatar(name: name, size: space.xl4 + space.sm),
                SizedBox(width: space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, style: context.text.h2),
                      SizedBox(height: space.xs),
                      RatingStars(value: trip.driverRatingAvg, size: space.lg),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: space.md),
          AppCard(
            child: Column(
              children: [
                _DetailRow(
                  icon: AppIcons.clock,
                  label: 'وقت الانطلاق',
                  value: formatTime(trip.departureTime),
                ),
                if (trip.vehicle != null)
                  _DetailRow(
                    icon: AppIcons.car,
                    label: 'المركبة',
                    value: '${trip.vehicle!.label} · ${trip.vehicle!.color}',
                  ),
                _DetailRow(
                  icon: AppIcons.seat,
                  label: 'المقاعد المتاحة',
                  value: '${trip.seatsAvailable} من ${trip.seatsTotal}',
                ),
                _DetailRow(
                  icon: AppIcons.cash,
                  label: 'السعر للمقعد',
                  value: formatPrice(trip.pricePerSeat),
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
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
            Text(label, style: context.text.body.copyWith(color: colors.textSecondary)),
            const Spacer(),
            Text(
              value,
              style: context.text.bodyStrong.tabular.copyWith(color: colors.textPrimary),
            ),
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
