import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../booking/booking_api.dart';
import '../booking/booking_controller.dart';
import '../booking/booking_screen.dart';
import 'trip_models.dart';
import 'trip_search_controller.dart';

/// Read-only expanded view of a trip. Tapping "احجز مقعد" opens the booking
/// form (seat count, pickup/dropoff, confirm).
///
/// Per the hand-off this screen opens on a **pine hero**: the route rail on a
/// `primary` field carrying the two cities, the departure time and the day. It
/// is the one card that answers "is this the trip I want?" before any of the
/// supporting detail. Everything under it — who is driving, what they drive,
/// how many seats are left — is confirmation, not discovery.
///
/// The price rides in the bottom bar next to the CTA rather than in the detail
/// list, so the number the rider is agreeing to is never scrolled off screen.
///
/// ## Contrast on the pine field
///
/// Same rule as the confirmation screen: hierarchy comes from size and weight,
/// not opacity. Every glyph on the hero is full `onPrimary` (7.93 light / 7.64
/// dark). The trip-type chip is a **pre-blended opaque** fill
/// (`onPrimary` at 16% composited into `primary` once, not a live alpha wash),
/// which measures 5.33 light / 5.79 dark against its `onPrimary` ink — see the
/// enforced contract in `contrast_test.dart`.
class TripDetailsScreen extends StatelessWidget {
  const TripDetailsScreen({super.key, required this.trip});

  final TripSummary trip;

  /// Alpha of the on-primary ink pre-blended into the pine field for the hero
  /// chip. Blended once into an opaque colour, never applied live.
  static const double heroChipBlend = 0.16;

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
    final corridor = _corridor(context);

    // Eligibility: a women/family trip only accepts female riders. The rider's
    // gender is always set (profile completion is required to reach this app),
    // so we can block ineligible riders in the UI before they hit the 403.
    final riderGender = context.watch<AuthController>().user?.gender;
    final eligible = trip.tripType != TripType.womenFamily ||
        riderGender == Gender.female;

    return AppScaffold(
      title: 'تفاصيل الرحلة',
      scrollable: true,
      bottomBar: _BookBar(
        pricePerSeat: trip.pricePerSeat,
        eligible: eligible,
        onBook: () => _openBooking(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: space.md),
          _TripHero(
            originCity: corridor?.originCity,
            destCity: corridor?.destCity,
            departureTime: trip.departureTime,
            womenFamily: trip.tripType == TripType.womenFamily,
          ),
          if (!eligible) ...[
            SizedBox(height: space.md),
            const _EligibilityNote(),
          ],
          SizedBox(height: space.md),
          _DriverCard(name: name, trip: trip),
          SizedBox(height: space.md),
          _FactsCard(trip: trip),
        ],
      ),
    );
  }
}

/// The pine hero: the route, the clock and the day, on a `primary` field.
class _TripHero extends StatelessWidget {
  const _TripHero({
    required this.originCity,
    required this.destCity,
    required this.departureTime,
    required this.womenFamily,
  });

  final String? originCity;
  final String? destCity;
  final DateTime departureTime;
  final bool womenFamily;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final ink = colors.onPrimary;

    return Container(
      padding: EdgeInsets.all(space.xl),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: context.radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RouteRail(
            onPrimaryField: true,
            origin: _HeroEndpoint(
              city: originCity,
              trailing: Text(
                formatTime(departureTime),
                style: context.text.h1.tabular.copyWith(color: ink),
              ),
            ),
            destination: _HeroEndpoint(
              city: destCity,
              trailing: Text(
                formatDayShortBaghdad(departureTime),
                style: context.text.body.copyWith(color: ink),
              ),
            ),
          ),
          if (womenFamily) ...[
            SizedBox(height: space.lg),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: _HeroChip(label: 'نسائية/عائلية', icon: AppIcons.users),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroEndpoint extends StatelessWidget {
  const _HeroEndpoint({required this.city, required this.trailing});

  final String? city;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            city == null ? 'الرحلة' : cityArName(city!),
            style: context.text.h2.copyWith(color: context.colors.onPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: context.space.sm),
        trailing,
      ],
    );
  }
}

/// A chip that lives on the pine field. Its fill is composited **once** into an
/// opaque colour so the measured ratio can't drift with whatever sits behind it.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.md, vertical: space.xs),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.onPrimary
              .withValues(alpha: TripDetailsScreen.heroChipBlend),
          colors.primary,
        ),
        borderRadius: context.radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onPrimary),
          SizedBox(width: space.xs),
          Text(
            label,
            style: context.text.caption.copyWith(
              color: colors.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is driving.
class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.name, required this.trip});

  final String name;
  final TripSummary trip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
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
                    RatingStars(value: trip.driverRatingAvg, size: space.lg),
                    if (trip.driverGender != null) ...[
                      SizedBox(width: space.sm),
                      Text(
                        trip.driverGender == Gender.female ? 'سائقة' : 'سائق',
                        style: context.text.caption
                            .copyWith(color: colors.textMuted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The supporting detail: the car and what is left of it.
class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.trip});

  final TripSummary trip;

  @override
  Widget build(BuildContext context) {
    final vehicle = trip.vehicle;
    return AppCard(
      child: Column(
        children: [
          if (vehicle != null)
            _DetailRow(
              icon: AppIcons.car,
              label: 'المركبة',
              value: '${vehicle.label} · ${vehicle.color}',
            ),
          _DetailRow(
            icon: AppIcons.seat,
            label: 'المقاعد',
            last: true,
            valueWidget: SeatAvailability(
              total: trip.seatsTotal,
              available: trip.seatsAvailable,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// The price and the CTA, together. The rider never has to scroll back up to
/// check what they are about to agree to.
class _BookBar extends StatelessWidget {
  const _BookBar({
    required this.pricePerSeat,
    required this.eligible,
    required this.onBook,
  });

  final int pricePerSeat;
  final bool eligible;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('السعر للمقعد',
                style: context.text.body.copyWith(color: colors.textSecondary)),
            const Spacer(),
            Text(
              formatPrice(pricePerSeat),
              style: context.text.h1.tabular.copyWith(color: colors.primary),
            ),
          ],
        ),
        SizedBox(height: space.md),
        AppButton(
          label: eligible ? 'احجز مقعد' : 'رحلة نسائية-عائلية',
          icon: AppIcons.seat,
          onPressed: eligible ? onBook : null,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
    this.last = false,
  }) : assert(value != null || valueWidget != null);

  final IconData icon;
  final String label;
  final String? value;

  /// Rendered instead of [value] when the row shows a graphic rather than text
  /// (the seats row draws [SeatGlyphs]).
  final Widget? valueWidget;
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
            valueWidget ??
                Text(
                  value!,
                  style: context.text.bodyStrong.tabular
                      .copyWith(color: colors.textPrimary),
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
        // Opaque tonal, not an alpha tint: the note sits on the page background
        // here but on a card elsewhere, and a live tint measures differently
        // on each.
        color: colors.infoTonal,
        borderRadius: context.radii.fieldLgAll,
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
              style: context.text.body.copyWith(color: colors.info),
            ),
          ),
        ],
      ),
    );
  }
}
