import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'booking_models.dart';
import 'my_bookings_controller.dart';

/// "حجوزاتي": the rider's bookings, filtered upcoming/past.
///
/// Per the hand-off: upcoming and past are a *filter*, not two stacked
/// sections — a rider opening this screen almost always wants the next trip,
/// and shouldn't scroll past history to reach it. Each card carries a status
/// stripe along its top edge so state is readable before any text is.
///
/// Upcoming CONFIRMED bookings can be cancelled (with a confirm dialog; the
/// backend enforces the free-cancel cutoff and its error is surfaced).
///
/// Each card also shows the two points the rider chose — tappable, so they can
/// check on a map that the pickup really is their gate and not the next street
/// — and, once the trip is theirs, the driver's number with call and WhatsApp.
/// The number comes from the server (`GET /trips/:id/contacts`), which answers
/// only for a live booking; a cancelled one loses it.
///
/// Refreshes on pull, and polls every [kBookingsPollInterval] while there is
/// anything live to learn about — a driver can start, complete or cancel the
/// trip from their side, and the rider should not have to leave the screen and
/// come back to find out.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _showPast = false;

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
    _snack(err);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Open the rate sheet for a completed ride.
  ///
  /// The sheet is the shared [RateSheet] — the same one the driver uses to rate
  /// riders, only the words differ.
  Future<void> _onRate(MyBookingsController c, Booking booking) async {
    await showRateSheet(
      context,
      title: 'قيّم السائق',
      name: booking.driverName ?? 'السائق',
      commentHint: 'كيف كانت الرحلة مع هذا السائق؟',
      onSubmit: (score, comment) =>
          c.rateDriver(bookingId: booking.id, score: score, comment: comment),
    );
  }

  /// Jump to «سابقة» and rate the oldest ride still waiting on one.
  Future<void> _onRatePrompt(MyBookingsController c) async {
    final pending = c.awaitingRating;
    if (pending.isEmpty) return;
    final booking = pending.first;
    // The card lives under «سابقة»; land the rider there so closing the sheet
    // leaves them looking at the thing they just rated, not at an unrelated
    // list of upcoming trips.
    setState(() => _showPast = true);
    await _onRate(c, booking);
  }

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
    final c = context.watch<MyBookingsController>();

    return PollingScope(
      interval: kBookingsPollInterval,
      // A finished history cannot change on its own; asking about it forever
      // is the definition of polling a screen with nothing to learn.
      enabled: c.hasLiveBookings,
      onPoll: c.refreshSilently,
      child: _body(c),
    );
  }

  Widget _body(MyBookingsController c) {
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
        MyBookingsStatus.loaded => c.isEmpty
            ? const _EmptyView()
            : _BookingsList(
                controller: c,
                showPast: _showPast,
                onSelectPast: (v) => setState(() => _showPast = v),
                onCancel: _onCancel,
                onShowPoint: _onShowPoint,
                onContactUnavailable: _snack,
                onRate: _onRate,
                onRatePrompt: _onRatePrompt,
              ),
      },
    );
  }
}

/// How often حجوزاتي re-asks while a booking is still live.
///
/// 30 seconds, twice the results interval: what changes here is driver-driven
/// and rarely urgent to the second — the rider is waiting for a start or a
/// cancellation, not for a listing to appear before someone else takes it.
/// The cancellation that IS urgent arrives through the notification poll,
/// which is separate and does not depend on this screen being open.
const Duration kBookingsPollInterval = Duration(seconds: 30);

class _BookingsList extends StatelessWidget {
  const _BookingsList({
    required this.controller,
    required this.showPast,
    required this.onSelectPast,
    required this.onCancel,
    required this.onShowPoint,
    required this.onContactUnavailable,
    required this.onRate,
    required this.onRatePrompt,
  });

  final MyBookingsController controller;
  final bool showPast;
  final ValueChanged<bool> onSelectPast;
  final Future<void> Function(MyBookingsController, Booking) onCancel;
  final Future<void> Function(LocationPoint, String) onShowPoint;
  final ValueChanged<String> onContactUnavailable;
  final Future<void> Function(MyBookingsController, Booking) onRate;
  final Future<void> Function(MyBookingsController) onRatePrompt;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final upcoming = controller.upcoming;
    final past = controller.past;
    final shown = showPast ? past : upcoming;

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: controller.refreshSilently,
      child: ListView(
        padding: EdgeInsets.all(space.lg),
        children: [
          // The prompt the rider meets on their next visit after a trip ends.
          // Above the filter because it is the one thing on this screen that is
          // asking them for something — and because the card it leads to lives
          // under «سابقة», which is not the tab they open on.
          if (controller.awaitingRating.isNotEmpty) ...[
            _RatePrompt(
              count: controller.awaitingRating.length,
              onTap: () => onRatePrompt(controller),
            ),
            SizedBox(height: space.md),
          ],
          Row(
            children: [
              _FilterPill(
                label: 'قادمة',
                count: upcoming.length,
                selected: !showPast,
                onTap: () => onSelectPast(false),
              ),
              SizedBox(width: space.sm),
              _FilterPill(
                label: 'سابقة',
                count: past.length,
                selected: showPast,
                onTap: () => onSelectPast(true),
              ),
            ],
          ),
          SizedBox(height: space.lg),
          if (shown.isEmpty)
            _FilterEmpty(showPast: showPast)
          else
            for (final b in shown) ...[
              _BookingCard(
                booking: b,
                past: showPast,
                cancelling: controller.isCancelling(b.id),
                contact: controller.contactFor(b.id),
                onCancel: controller.canCancel(b)
                    ? () => onCancel(controller, b)
                    : null,
                onShowPoint: onShowPoint,
                onContactUnavailable: onContactUnavailable,
                onRate: b.canRate ? () => onRate(controller, b) : null,
              ),
              SizedBox(height: space.md),
            ],
        ],
      ),
    );
  }
}

/// «قيّم رحلتك الأخيرة» — the prompt a rider meets after a trip completes.
///
/// The driver's `ratingAvg` is exactly what riders use to choose a trip, and
/// before this existed it could never be populated: the driver could rate the
/// rider, and the rider had nowhere to rate back. A dead trust signal is worse
/// than a missing one, because the empty stars look like a judgement.
///
/// A tonal card rather than a toast: it must survive being ignored once.
class _RatePrompt extends StatelessWidget {
  const _RatePrompt({required this.count, required this.onTap});

  /// How many completed rides are still unrated.
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radii.cardAll,
        child: Ink(
          decoration: BoxDecoration(
            // Opaque tonal, never an alpha tint — this sits on the page
            // background and its contrast must not depend on what is behind it.
            color: colors.primaryTonal,
            borderRadius: context.radii.cardAll,
          ),
          padding: EdgeInsets.all(space.lg),
          child: Row(
            children: [
              Icon(AppIcons.star, color: colors.primary, size: space.xl),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _promptTitle(count),
                      style: context.text.bodyStrong
                          .copyWith(color: colors.textPrimary),
                    ),
                    SizedBox(height: space.xs),
                    Text(
                      'تقييمك يساعد بقية الركّاب على اختيار سائق.',
                      style: context.text.caption
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(width: space.sm),
              Icon(AppIcons.chevronLeft, color: colors.primary, size: space.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arabic plural agreement, and no separator anywhere near the numeral: at 3+
/// the digit leads the phrase, and «رحلة» / «رحلتان» carry no digit at all.
String _promptTitle(int count) => switch (count) {
      1 => 'قيّم رحلتك الأخيرة',
      2 => 'قيّم رحلتيك الأخيرتين',
      _ => 'لديك ${formatCount(count)} رحلات بانتظار تقييمك',
    };

/// Upcoming / past selector. The count rides inside the pill so the rider can
/// see there *is* history without switching to it.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label ${formatCount(count)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: space.lg),
            decoration: BoxDecoration(
              color: selected ? colors.textPrimary : colors.surface,
              borderRadius: context.radii.pillAll,
              border: Border.all(
                color: selected ? colors.textPrimary : colors.border,
              ),
            ),
            child: Text(
              '$label ${formatCount(count)}',
              style: context.text.label.copyWith(
                // On the inverse pill the ink is the page background, which is
                // the highest-contrast pairing available (15.39 / 16.93).
                color: selected ? colors.background : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.showPast});

  final bool showPast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.space.xl3),
      child: Text(
        showPast ? 'لا توجد رحلات سابقة.' : 'لا توجد رحلات قادمة.',
        textAlign: TextAlign.center,
        style: context.text.body.copyWith(color: context.colors.textMuted),
      ),
    );
  }
}

/// A booking as a card with a status stripe along its top edge, the route on
/// the rail, and the fare. Past bookings are recessed rather than raised.
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.past,
    required this.cancelling,
    required this.onShowPoint,
    required this.onContactUnavailable,
    this.contact,
    this.onCancel,
    this.onRate,
  });

  final Booking booking;
  final bool past;
  final bool cancelling;

  /// The driver's number, or null when the server did not give one (a past or
  /// cancelled booking). Null draws no contact section at all.
  final TripContact? contact;
  final Future<void> Function(LocationPoint, String) onShowPoint;
  final ValueChanged<String> onContactUnavailable;
  final VoidCallback? onCancel;

  /// Rate the driver of this completed ride. Null once rated, or when the ride
  /// never happened — the server would refuse either, and an action that
  /// answers with an error is worse than no action.
  final VoidCallback? onRate;

  /// Hand-off stripe thickness.
  static const double _stripe = 4;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final trip = booking.trip;
    final corridor = trip?.corridor;
    final tone = _statusTone(booking.status, colors);

    return ClipRRect(
      borderRadius: context.radii.cardAll,
      child: AppCard(
        muted: past,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status, readable before any text is. The stripe is deliberately
            // NOT held to 4.5:1 — it is decorative and fully redundant with the
            // status badge on the rail below it, so nothing is conveyed by
            // colour alone (`completed` even draws it in `borderStrong`).
            Container(height: _stripe, color: tone),
            Padding(
              padding: EdgeInsets.all(space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RouteRail(
                    variant: RouteRailVariant.compact,
                    origin: _EndpointRow(
                      city: corridor?.originCity,
                      trailing: trip == null
                          ? null
                          : Text(
                              formatTime(trip.departureTime),
                              style: context.text.h2.tabular
                                  .copyWith(color: colors.textPrimary),
                            ),
                    ),
                    destination: _EndpointRow(
                      city: corridor?.destCity,
                      trailing: _statusBadge(booking.status),
                    ),
                  ),
                  SizedBox(height: space.md),
                  Divider(height: 1, color: colors.border),
                  SizedBox(height: space.sm),
                  // The rider's own two points, tappable. They picked these on
                  // a map; being able to look again is how they check the
                  // pickup is their gate and not the next street over.
                  MapPointRow(
                    title: 'نقطة الانطلاق',
                    point: booking.pickup,
                    icon: AppIcons.mapPin,
                    onTap: () =>
                        onShowPoint(booking.pickup, 'نقطة الانطلاق'),
                  ),
                  MapPointRow(
                    title: 'نقطة النزول',
                    point: booking.dropoff,
                    icon: AppIcons.route,
                    onTap: () =>
                        onShowPoint(booking.dropoff, 'نقطة النزول'),
                  ),
                  SizedBox(height: space.sm),
                  Divider(height: 1, color: colors.border),
                  SizedBox(height: space.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${formatSeats(booking.seatCount)} · نقداً',
                          style: context.text.body
                              .copyWith(color: colors.textSecondary)),
                      const Spacer(),
                      Text(
                        formatPrice(booking.fare),
                        style: context.text.title.tabular
                            .copyWith(color: colors.primary),
                      ),
                    ],
                  ),
                  // Present only because the server answered — a rider with no
                  // live booking on this trip gets a 403 and no row.
                  if (contact != null) ...[
                    SizedBox(height: space.md),
                    Divider(height: 1, color: colors.border),
                    SizedBox(height: space.md),
                    ContactRow(
                      phone: contact!.phone,
                      name: contact!.name,
                      roleLabel: 'السائق',
                      launcher: context.read<LinkLauncher>(),
                      onUnavailable: onContactUnavailable,
                    ),
                  ],
                  if (onCancel != null) ...[
                    SizedBox(height: space.md),
                    AppButton(
                      label: 'إلغاء الحجز',
                      // The hand-off's soft danger: a cancel should be findable
                      // without shouting louder than the booking itself.
                      variant: AppButtonVariant.dangerTonal,
                      icon: AppIcons.close,
                      loading: cancelling,
                      onPressed: onCancel,
                    ),
                  ],
                  if (onRate != null) ...[
                    SizedBox(height: space.md),
                    AppButton(
                      label: 'قيّم السائق',
                      // Secondary, not primary: a finished ride is not asking
                      // for anything, and the card is history the rider is
                      // reading rather than a task waiting on them.
                      variant: AppButtonVariant.secondary,
                      icon: AppIcons.star,
                      onPressed: onRate,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A city on the booking rail with its time / status on the trailing edge.
class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.city, required this.trailing});

  final String? city;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            city == null ? 'رحلة' : cityArName(city!),
            style: context.text.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

Color _statusTone(BookingStatus status, AppColors c) => switch (status) {
      BookingStatus.confirmed => c.success,
      BookingStatus.onboard => c.info,
      BookingStatus.completed => c.borderStrong,
      BookingStatus.cancelled => c.danger,
      BookingStatus.noShow => c.warning,
      BookingStatus.unknown => c.borderStrong,
    };

/// The status as a badge, not a pill: it rides on the rail's trailing edge
/// beside the destination, so it has to stay narrow enough that the city name
/// never ellipsises to make room for it.
Widget _statusBadge(BookingStatus status) {
  final (String label, AppBadgeTone tone, IconData icon) = switch (status) {
    BookingStatus.confirmed => ('مؤكد', AppBadgeTone.success, AppIcons.success),
    BookingStatus.onboard => ('على المتن', AppBadgeTone.info, AppIcons.car),
    BookingStatus.completed => ('مكتملة', AppBadgeTone.neutral, AppIcons.check),
    BookingStatus.cancelled => ('ملغاة', AppBadgeTone.danger, AppIcons.close),
    BookingStatus.noShow => ('لم تحضر', AppBadgeTone.warning, AppIcons.warning),
    BookingStatus.unknown => ('—', AppBadgeTone.neutral, AppIcons.info),
  };
  return AppBadge(label: label, tone: tone, icon: icon);
}

Future<bool?> _confirmCancelDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final space = ctx.space;
      final colors = ctx.colors;
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: ctx.radii.cardAll),
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
                'هل تريد إلغاء هذا الحجز؟ الإلغاء المجاني متاح حتى ١٥ دقيقة قبل المغادرة.',
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
                color: colors.primaryTonal,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(AppIcons.seat, color: colors.primary, size: space.xl2),
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
                color: colors.dangerTonal,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text(message, style: context.text.title, textAlign: TextAlign.center),
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
