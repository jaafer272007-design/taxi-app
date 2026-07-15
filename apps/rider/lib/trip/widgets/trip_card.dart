import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../trip_format.dart';
import '../trip_models.dart';

/// A driver-posted trip as a tappable card: driver identity + rating, departure
/// time, vehicle, price per seat, and a seats-available pill (warning when only
/// the last seat remains). Token-only.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.onTap});

  final TripSummary trip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final text = context.text;
    final name = (trip.driverName?.trim().isNotEmpty ?? false)
        ? trip.driverName!.trim()
        : 'سائق';

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Driver + departure time.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: name),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: text.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: space.xs),
                    Row(
                      children: [
                        RatingStars(value: trip.driverRatingAvg, size: space.lg),
                        if (trip.driverGender != null) ...[
                          SizedBox(width: space.sm),
                          Text(
                            trip.driverGender == Gender.female
                                ? 'سائقة'
                                : 'سائق',
                            style: text.caption.copyWith(color: colors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: space.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'وقت الانطلاق',
                    style: text.caption.copyWith(color: colors.textMuted),
                  ),
                  SizedBox(height: space.xs),
                  Text(
                    formatTime(trip.departureTime),
                    style: text.h2.tabular.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
          if (trip.tripType == TripType.womenFamily) ...[
            SizedBox(height: space.md),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppPill(
                label: 'نسائية/عائلية',
                tone: AppBadgeTone.info,
                icon: AppIcons.users,
              ),
            ),
          ],
          if (trip.vehicle != null) ...[
            SizedBox(height: space.md),
            Row(
              children: [
                Icon(AppIcons.car, size: space.lg, color: colors.textMuted),
                SizedBox(width: space.sm),
                Expanded(
                  child: Text(
                    '${trip.vehicle!.label} · ${trip.vehicle!.color}',
                    style: text.body.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formatPrice(trip.pricePerSeat),
                style: text.title.tabular.copyWith(color: colors.primary),
              ),
              Text(
                ' / للمقعد',
                style: text.caption.copyWith(color: colors.textMuted),
              ),
              const Spacer(),
              _SeatsPill(trip: trip),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeatsPill extends StatelessWidget {
  const _SeatsPill({required this.trip});

  final TripSummary trip;

  @override
  Widget build(BuildContext context) {
    if (trip.lastSeat) {
      return const AppPill(
        label: 'مقعد واحد فقط',
        tone: AppBadgeTone.warning,
        icon: AppIcons.seat,
      );
    }
    return AppPill(
      label: '${trip.seatsAvailable} مقاعد متاحة',
      tone: AppBadgeTone.success,
      icon: AppIcons.seat,
    );
  }
}
