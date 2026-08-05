import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'driver_trip_models.dart';
import 'rate_rider_sheet.dart';
import 'trip_detail_controller.dart';

/// Driver's view of ONE of their trips: the trip's info, the list of bookings
/// (rider name, seats, pickup/dropoff, status) and every lifecycle action —
/// start, per-rider onboard / no-show, complete (with a cash summary), cancel,
/// and post-completion rider rating.
///
/// ## Getting to the rider
///
/// Knowing the neighbourhood is not enough to complete a pickup. Each booking's
/// pickup and dropoff are tappable and open on a map, with a hand-off to the
/// driver's own navigation app; and each rider's number sits on their row with
/// call and WhatsApp beside it — because in a real كراج ride the driver rings
/// to pin down the exact spot, and that call is part of the job, not a fallback.
///
/// Numbers appear only because the server returned them: `GET
/// /trips/:id/contacts` answers for the trip's own driver and nobody else.
///
/// Refreshes on pull, and polls every [kTripDetailPollInterval] while the trip
/// is live — a new booking arriving is exactly the thing a driver waiting to
/// set off needs to see without tapping anything.
class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

/// How often a live trip's bookings are re-fetched.
///
/// 20 seconds: between the rider's 15s results poll and the 30s bookings poll.
/// A driver watching seats fill is waiting on other people's taps, so it has
/// to feel prompt — but this screen is open for long stretches while parked at
/// the كراج, and every tick is a request on a metered connection.
const Duration kTripDetailPollInterval = Duration(seconds: 20);

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
        shape: RoundedRectangleBorder(borderRadius: ctx.radii.cardAll),
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

  /// Open one end of a booking on a map, with the hand-off to navigation.
  Future<void> _onShowPoint(LocationPoint point, String title) async {
    await showMapView(
      context,
      point: point,
      launcher: context.read<LinkLauncher>(),
      title: title,
      onNavigationUnavailable: () =>
          _snack('لا يوجد تطبيق خرائط على هذا الجهاز.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TripDetailController>();
    final space = context.space;

    return PollingScope(
      interval: kTripDetailPollInterval,
      // Nothing left to learn about a finished trip.
      enabled: c.isLive,
      onPoll: c.refreshSilently,
      child: AppScaffold(
        title: 'تفاصيل الرحلة',
        padded: false,
        bottomBar: _bottomBar(c),
        body: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: c.refreshSilently,
          child: ListView(
            padding: EdgeInsets.all(space.lg),
            children: [
              _TripHero(controller: c),
              if (c.summary != null) ...[
                SizedBox(height: space.md),
                _SummaryCard(summary: c.summary!),
              ],
              SizedBox(height: space.lg),
              Text('الحجوزات',
                  style: context.text.h2
                      .copyWith(color: context.colors.textPrimary)),
              SizedBox(height: space.md),
              _bookingsSection(c),
            ],
          ),
        ),
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
                onShowPickup: () =>
                    _onShowPoint(b.pickup, 'نقطة انطلاق الراكب'),
                onShowDropoff: () =>
                    _onShowPoint(b.dropoff, 'نقطة نزول الراكب'),
                onContactUnavailable: _snack,
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
      // The cash rides on the button. Completing the trip IS the collection, so
      // the driver should see the figure they are about to be holding at the
      // moment they commit — not have to remember it from the hero.
      return AppButton(
        label: 'أنهِ الرحلة · تحصيل ${formatPrice(c.expectedCash)}',
        icon: AppIcons.check,
        loading: c.tripActionInFlight,
        onPressed: () => _onComplete(c),
      );
    }
    return null;
  }
}

/// The pine hero: the route on the rail, then the three figures a driver checks
/// mid-trip — when it leaves, how many are on board, and how much cash that is.
///
/// Cash gets a place on the hero because it is the number the driver is
/// carrying. Its meaning shifts with the trip's state (booked before departure,
/// actually-on-board after), so the label shifts with it rather than quietly
/// changing what the same word means — see `TripDetailController.expectedCash`.
class _TripHero extends StatelessWidget {
  const _TripHero({required this.controller});

  final TripDetailController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final trip = controller.trip;
    final corridor = controller.corridor;
    final ink = colors.onPrimary;
    final moving = controller.isEnRoute || controller.isDone;

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
              city: corridor?.originCity,
              trailing: Text(
                formatTime(trip.departureTime),
                style: context.text.h1.tabular.copyWith(color: ink),
              ),
            ),
            destination: _HeroEndpoint(
              city: corridor?.destCity,
              trailing: Text(
                formatDayShortBaghdad(trip.departureTime),
                style: context.text.body.copyWith(color: ink),
              ),
            ),
          ),
          SizedBox(height: space.lg),
          Row(
            children: [
              OnPrimaryChip(
                label: tripStatusLabel(trip.status),
                icon: AppIcons.route,
              ),
              if (trip.tripType == TripType.womenFamily) ...[
                SizedBox(width: space.sm),
                const OnPrimaryChip(
                  label: 'نسائية/عائلية',
                  icon: AppIcons.users,
                ),
              ],
            ],
          ),
          SizedBox(height: space.lg),
          Divider(height: 1, color: onPrimaryFill(colors, 0.28)),
          SizedBox(height: space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HeroStat(
                  label: moving ? 'على المتن' : 'محجوز',
                  value: formatCount(controller.seatsOnBoard),
                  unit: 'من ${formatCount(trip.seatsTotal)}',
                ),
              ),
              Expanded(
                child: _HeroStat(
                  // "للتحصيل" once moving, matching the CTA word for word: the
                  // en-route figure counts only riders actually on board, so
                  // calling it "expected" would imply it includes the confirmed
                  // rider still standing at the kerb. It does not.
                  label: moving ? 'للتحصيل' : 'نقد محجوز',
                  value: formatIqd(controller.expectedCash),
                  unit: iqdSuffix,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A city on the hero rail, with its time / date on the trailing edge.
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

/// One figure on the hero. Hierarchy is size, not opacity — every glyph here is
/// full `onPrimary`.
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.onPrimary;
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.text.caption.copyWith(color: ink)),
        SizedBox(height: space.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: context.text.h1.tabular.copyWith(color: ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: space.xs),
            Text(unit, style: context.text.caption.copyWith(color: ink)),
          ],
        ),
      ],
    );
  }
}

/// The receipt after a trip settles: who rode and what the driver is holding.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final TripCompletionSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Container(
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        // Opaque tonal — this sits on the page background here, but the same
        // receipt block would measure differently on a card.
        color: colors.successTonal,
        borderRadius: context.radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.success, size: space.xl, color: colors.success),
              SizedBox(width: space.sm),
              Text('اكتملت الرحلة',
                  style: context.text.title.copyWith(color: colors.success)),
            ],
          ),
          SizedBox(height: space.md),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: 'ركّاب',
                  value: formatCount(summary.ridersCount),
                ),
              ),
              Expanded(
                child: _SummaryStat(
                  label: 'مقاعد ركبت',
                  value: formatCount(summary.seatsRidden),
                ),
              ),
              Expanded(
                child: _SummaryStat(
                  label: 'نقد محصّل',
                  value: formatIqd(summary.cashCollected),
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
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: context.text.caption.copyWith(color: colors.success)),
        SizedBox(height: space.xs),
        Text(value,
            style: context.text.h2.tabular.copyWith(color: colors.success),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
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
    required this.onShowPickup,
    required this.onShowDropoff,
    required this.onContactUnavailable,
  });

  final TripDetailController controller;
  final TripBooking booking;
  final VoidCallback onOnboard;
  final VoidCallback onNoShow;
  final VoidCallback onRate;
  final VoidCallback onShowPickup;
  final VoidCallback onShowDropoff;
  final ValueChanged<String> onContactUnavailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final name = booking.riderName ?? 'راكب';
    final inFlight = controller.bookingActionInFlight(booking.id);
    final contact = controller.contactFor(booking.id);

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
                    // "بـ" and not " · ": formatPrice always STARTS with an
                    // Arabic-Indic digit, and `٠` is a dot — the separator
                    // fused onto the fare, so ٦٬٠٠٠ read as ٦٬٠٠٠٠ on the very
                    // screen where the driver counts cash against a passenger.
                    // A strong Arabic letter can neither be mistaken for a
                    // digit nor be reordered by bidi.
                    Text('${formatSeats(booking.seatCount)} بـ${formatPrice(booking.fare)}',
                        style: context.text.caption
                            .copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: space.sm),
              bookingStatusPill(booking.status),
            ],
          ),
          SizedBox(height: space.sm),
          // Tappable, because a neighbourhood name does not get a car to a
          // door. Static text if the API sent no coordinates — a row that
          // opens a map on Null Island would be worse than one that does
          // nothing.
          MapPointRow(
            title: 'نقطة الانطلاق',
            point: booking.pickup,
            icon: AppIcons.mapPin,
            onTap: onShowPickup,
          ),
          MapPointRow(
            title: 'نقطة النزول',
            point: booking.dropoff,
            icon: AppIcons.route,
            onTap: onShowDropoff,
          ),
          // Only present because the server said this driver may have it.
          if (contact != null) ...[
            SizedBox(height: space.sm),
            Divider(height: 1, color: colors.border),
            SizedBox(height: space.md),
            ContactRow(
              phone: contact.phone,
              name: contact.name,
              roleLabel: 'الراكب',
              launcher: context.read<LinkLauncher>(),
              onUnavailable: onContactUnavailable,
              // The name is already the card's headline; repeating it above the
              // number would be the third time it appears on one card.
              compact: true,
            ),
          ],
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

/// The Arabic name of a trip state. One source of truth — the pill, the compact
/// badge and the hero chip all read from here, so a state can never be called
/// two different things on two screens.
String tripStatusLabel(TripStatus status) => switch (status) {
      TripStatus.open => 'مفتوحة',
      TripStatus.locked => 'مكتملة الحجز',
      TripStatus.enRoute => 'جارية',
      TripStatus.completed || TripStatus.settled => 'منتهية',
      TripStatus.cancelled => 'ملغاة',
      TripStatus.unknown => '—',
    };

AppBadgeTone _tripStatusTone(TripStatus status) => switch (status) {
      TripStatus.open => AppBadgeTone.success,
      TripStatus.locked => AppBadgeTone.warning,
      TripStatus.enRoute => AppBadgeTone.info,
      TripStatus.completed || TripStatus.settled => AppBadgeTone.neutral,
      TripStatus.cancelled => AppBadgeTone.danger,
      TripStatus.unknown => AppBadgeTone.neutral,
    };

/// Status pill for a trip (shared with the trips list mapping).
Widget tripStatusPill(TripStatus status) => AppPill(
      label: tripStatusLabel(status),
      tone: _tripStatusTone(status),
    );

/// The same status as a compact [AppBadge], for rails and list rows where a
/// full pill would squeeze the city name into an ellipsis.
Widget tripStatusBadge(TripStatus status) => AppBadge(
      label: tripStatusLabel(status),
      tone: _tripStatusTone(status),
    );

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
