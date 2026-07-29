import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../trip_models.dart';

/// A driver-posted trip as a tappable card, in the Masar anatomy.
///
/// **Time is the headline.** Price is fixed per corridor, so it cannot
/// differentiate one trip from another — departure time can. The time therefore
/// takes the `display` style on the leading edge, with the driver and vehicle
/// secondary beside it and the price sitting quiet on the trailing edge.
/// Availability is drawn with [SeatAvailability] rather than spelled out.
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── The headline: departure time ──────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatTime(trip.departureTime),
                      style: text.display.tabular
                          .copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      'الانطلاق',
                      style: text.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
                SizedBox(width: space.md),
                VerticalDivider(width: 1, thickness: 1, color: colors.border),
                SizedBox(width: space.md),
                // ── Driver + vehicle ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: text.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: space.xs),
                      Row(
                        children: [
                          RatingStars(
                              value: trip.driverRatingAvg, size: space.lg),
                          if (trip.driverGender != null) ...[
                            SizedBox(width: space.sm),
                            Text(
                              trip.driverGender == Gender.female
                                  ? 'سائقة'
                                  : 'سائق',
                              style: text.caption
                                  .copyWith(color: colors.textMuted),
                            ),
                          ],
                        ],
                      ),
                      if (trip.vehicle != null) ...[
                        SizedBox(height: space.xs),
                        Text(
                          '${trip.vehicle!.label} · ${trip.vehicle!.color}',
                          style: text.caption
                              .copyWith(color: colors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: space.sm),
                // ── Price, quiet ─────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatPrice(trip.pricePerSeat),
                      style: text.bodyStrong.tabular
                          .copyWith(color: colors.primary),
                    ),
                    Text(
                      'للمقعد',
                      style: text.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: space.md),
          // ── Availability, drawn as seats ────────────────────────────────
          Row(
            children: [
              Expanded(
                child: SeatAvailability(
                  total: trip.seatsTotal,
                  available: trip.seatsAvailable,
                ),
              ),
              if (trip.tripType == TripType.womenFamily) ...[
                SizedBox(width: space.sm),
                const AppPill(
                  label: 'نسائية/عائلية',
                  tone: AppBadgeTone.info,
                  icon: AppIcons.users,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
