import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../booking/booking_api.dart';
import '../booking/booking_controller.dart';
import '../booking/booking_screen.dart';
import 'trip_format.dart';
import 'trip_models.dart';
import 'trip_search_controller.dart';

/// Read-only expanded view of a trip. Tapping "احجز مقعد" opens the booking
/// form (seat count, pickup/dropoff, confirm).
class TripDetailsScreen extends StatelessWidget {
  const TripDetailsScreen({super.key, required this.trip});

  final TripSummary trip;

  /// Resolve the trip's corridor (for endpoint city names) from the already-
  /// loaded corridors; null when unavailable (booking falls back to generic
  /// field labels).
  Corridor? _corridor(BuildContext context) {
    try {
      final corridors = context.read<TripSearchController>().corridors;
      for (final c in corridors) {
        if (c.id == trip.corridorId) return c;
      }
    } catch (_) {
      // No search controller in scope (e.g. isolated preview) — generic labels.
    }
    return null;
  }

  void _openBooking(BuildContext context) {
    final api = context.read<BookingApi>();
    final corridor = _corridor(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<BookingController>(
          create: (_) => BookingController(
            api: api,
            trip: trip,
            originCity: corridor?.originCity,
            destCity: corridor?.destCity,
          ),
          child: const BookingScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final name = (trip.driverName?.trim().isNotEmpty ?? false)
        ? trip.driverName!.trim()
        : 'سائق';

    // Eligibility: a women/family trip only accepts female riders. The rider's
    // gender is always set (profile completion is required to reach this app),
    // so we can block ineligible riders in the UI before they hit the 403.
    final riderGender = context.watch<AuthController>().user?.gender;
    final eligible = trip.tripType != TripType.womenFamily ||
        riderGender == Gender.female;

    return AppScaffold(
      title: 'تفاصيل الرحلة',
      scrollable: true,
      bottomBar: AppButton(
        label: eligible ? 'احجز مقعد' : 'رحلة نسائية-عائلية',
        icon: AppIcons.seat,
        onPressed: eligible ? () => _openBooking(context) : null,
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
                              style: context.text.caption
                                  .copyWith(color: context.colors.textMuted),
                            ),
                          ],
                        ],
                      ),
                      if (trip.tripType == TripType.womenFamily) ...[
                        SizedBox(height: space.sm),
                        const AppPill(
                          label: 'نسائية/عائلية',
                          tone: AppBadgeTone.info,
                          icon: AppIcons.users,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!eligible) ...[
            SizedBox(height: space.md),
            const _EligibilityNote(),
          ],
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

/// Non-judgmental note shown when a rider can't book a women/family trip.
class _EligibilityNote extends StatelessWidget {
  const _EligibilityNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.12),
        borderRadius: context.radii.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: space.xl, color: colors.info),
          SizedBox(width: space.md),
          Expanded(
            child: Text(
              'هذه رحلة نسائية-عائلية ومخصّصة للركّاب من النساء، لذلك لا يمكنك '
              'حجزها. اختر رحلة عامة للمتابعة.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
