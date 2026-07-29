import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'booking_confirmation_screen.dart';
import 'booking_controller.dart';
import 'booking_error.dart';
import 'booking_models.dart';

/// Reserve-a-seat: pick how many seats, set the door-to-door points on a map,
/// and confirm. Reads/writes a [BookingController] provided by the route that
/// opened this screen.
///
/// Laid out per the Masar hand-off: seats are *picked*, not stepped; pickup and
/// dropoff share one route-rail card; and the running total sits with the CTA
/// in the sticky bar rather than inline in the form.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  /// Open the map picker for the pickup or dropoff point, defaulting to the
  /// corridor city centre, and store the chosen point on the controller.
  Future<void> _pickPoint({required bool isPickup}) async {
    final c = context.read<BookingController>();
    final locationService = context.read<LocationService>();
    final geocoder = context.read<ReverseGeocoder>();

    final city = isPickup ? c.originCity : c.destCity;
    final cityName = city == null ? null : cityArName(city);
    final current = isPickup ? c.pickup : c.dropoff;
    final isSet = isPickup ? c.pickupSet : c.dropoffSet;

    final result = await showMapPicker(
      context,
      initialCenter: LocationPoint(
        lat: current.lat,
        lng: current.lng,
        label: isSet ? current.label : '',
      ),
      locationService: locationService,
      reverseGeocoder: geocoder,
      title: isPickup ? 'نقطة الانطلاق' : 'نقطة النزول',
      fallbackLabel:
          cityName == null ? 'النقطة المحددة' : '$cityName - النقطة المحددة',
    );
    if (result == null || !mounted) return;

    final point =
        GeoPoint(lat: result.lat, lng: result.lng, label: result.label);
    if (isPickup) {
      c.setPickupPoint(point);
    } else {
      c.setDropoffPoint(point);
    }
  }

  Future<void> _confirm() async {
    final c = context.read<BookingController>();
    final ok = await c.submit();
    if (!ok) return;
    if (!mounted) return;
    final result = c.result!;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BookingConfirmationScreen(
          seatCount: result.seatCount,
          fare: result.fare,
          departureTime: c.trip.departureTime,
          originCity: c.originCity,
          destCity: c.destCity,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BookingController>();
    final space = context.space;
    final error = c.error;
    final seatGone = error?.kind == BookingErrorKind.seatGone;
    final notEligible = error?.kind == BookingErrorKind.notEligible;

    return AppScaffold(
      title: 'حجز مقعد',
      scrollable: true,
      // Total + CTA travel together, so the fare is visible at the moment of
      // commitment rather than scrolled away up the form.
      bottomBar: _ConfirmBar(
        seatCount: c.seatCount,
        fare: c.fare,
        loading: c.submitting,
        onConfirm:
            (c.canSubmit && !seatGone && !notEligible) ? _confirm : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.md),
          _TripSummaryCard(controller: c),
          SizedBox(height: space.xl),
          const _SectionLabel('اختر مقاعدك'),
          SizedBox(height: space.sm),
          _SeatPicker(controller: c),
          SizedBox(height: space.xl),
          const _SectionLabel('من الباب إلى الباب'),
          SizedBox(height: space.sm),
          _DoorToDoorCard(
            controller: c,
            onPickPickup: () => _pickPoint(isPickup: true),
            onPickDropoff: () => _pickPoint(isPickup: false),
          ),
          SizedBox(height: space.lg),
          const _CashNote(),
          if (error != null) ...[
            SizedBox(height: space.lg),
            _ErrorBanner(
              error: error,
              onBack: (seatGone || notEligible)
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: context.text.label.copyWith(color: context.colors.textSecondary),
      );
}

/// Compact recap of the trip being booked: driver + departure time + unit price.
class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({required this.controller});

  final BookingController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final trip = controller.trip;
    final name = (trip.driverName?.trim().isNotEmpty ?? false)
        ? trip.driverName!.trim()
        : 'سائق';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: name),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: context.text.bodyStrong, maxLines: 1),
                    SizedBox(height: space.xs),
                    RatingStars(value: trip.driverRatingAvg, size: space.lg),
                  ],
                ),
              ),
              // Time is the headline here too.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatTime(trip.departureTime),
                      style: context.text.h1.tabular
                          .copyWith(color: colors.textPrimary)),
                  Text('الانطلاق',
                      style: context.text.caption
                          .copyWith(color: colors.textMuted)),
                ],
              ),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            children: [
              Icon(AppIcons.cash, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Text('السعر للمقعد',
                  style:
                      context.text.body.copyWith(color: colors.textSecondary)),
              const Spacer(),
              Text(formatPrice(trip.pricePerSeat),
                  style: context.text.bodyStrong.tabular
                      .copyWith(color: colors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tap the number of seats you want. Replaces the ± stepper: unavailable counts
/// are visibly dead rather than merely un-pressable, so the ceiling is legible
/// before you reach for it.
class _SeatPicker extends StatelessWidget {
  const _SeatPicker({required this.controller});

  final BookingController controller;

  /// A booking is capped at 4 seats regardless of vehicle size.
  static const int _maxOffered = 4;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final max = controller.maxSeats;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              for (var n = 1; n <= _maxOffered; n++) ...[
                if (n > 1) SizedBox(width: space.sm),
                Expanded(
                  child: _SeatTile(
                    n: n,
                    selected: controller.seatCount == n,
                    available: n <= max,
                    onTap: n <= max ? () => controller.setSeatCount(n) : null,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: space.md),
          Text(
            SeatGlyphs.label(controller.trip.seatsAvailable),
            style: context.text.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.n,
    required this.selected,
    required this.available,
    this.onTap,
  });

  final int n;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  /// Hand-off tile height; comfortably above the 48dp minimum.
  static const double _height = 76;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Unavailable counts use the recessed surface + muted ink rather than an
    // opacity wash: a translucent tile composites over whatever is behind it
    // and its contrast stops being predictable.
    final Color bg = selected
        ? colors.primary
        : available
            ? colors.surface
            : colors.surfaceMuted;
    final Color ink = selected
        ? colors.onPrimary
        : available
            ? colors.textSecondary
            : colors.textMuted;
    final Color border = selected ? colors.primary : colors.border;

    return Semantics(
      button: available,
      enabled: available,
      selected: selected,
      label: '${formatCount(n)} مقعد',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: context.radii.fieldAll,
            border: Border.all(color: border, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.seat, size: context.space.xl2, color: ink),
              SizedBox(height: context.space.xs),
              Text(formatCount(n),
                  style: context.text.label.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pickup and dropoff in a single route-rail card — one journey, not two
/// unrelated address fields.
class _DoorToDoorCard extends StatelessWidget {
  const _DoorToDoorCard({
    required this.controller,
    required this.onPickPickup,
    required this.onPickDropoff,
  });

  final BookingController controller;
  final VoidCallback onPickPickup;
  final VoidCallback onPickDropoff;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: RouteRail(
        divided: true,
        origin: _PointRow(
          title: 'نقطة الانطلاق',
          point: controller.pickup,
          isSet: controller.pickupSet,
          onTap: onPickPickup,
        ),
        destination: _PointRow(
          title: 'نقطة النزول',
          point: controller.dropoff,
          isSet: controller.dropoffSet,
          onTap: onPickDropoff,
        ),
      ),
    );
  }
}

/// One endpoint inside [_DoorToDoorCard]: label, the chosen address (or a
/// prompt), and a chevron into the map picker.
class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.title,
    required this.point,
    required this.isSet,
    required this.onTap,
  });

  final String title;
  final GeoPoint point;
  final bool isSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final hasLabel = isSet && point.label.trim().isNotEmpty;

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: context.text.caption
                            .copyWith(color: colors.textMuted)),
                    SizedBox(height: space.xs),
                    Text(
                      hasLabel
                          ? point.label.trim()
                          : 'حدّد النقطة على الخريطة',
                      style: hasLabel
                          ? context.text.bodyStrong
                              .copyWith(color: colors.textPrimary)
                          : context.text.body
                              .copyWith(color: colors.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: space.sm),
              Icon(AppIcons.chevronLeft,
                  size: space.lg, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "الدفع نقداً عند الرحلة" — informational (cash only in Phase 1), on the
/// opaque warning tonal so its contrast does not depend on what sits behind it.
class _CashNote extends StatelessWidget {
  const _CashNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: colors.warningTonal,
        borderRadius: context.radii.fieldLgAll,
      ),
      child: Row(
        children: [
          Icon(AppIcons.cash, size: space.xl, color: colors.warning),
          SizedBox(width: space.md),
          Expanded(
            child: Text('الدفع نقداً عند الرحلة — لا حاجة لبطاقة',
                style: context.text.label.copyWith(color: colors.warning)),
          ),
        ],
      ),
    );
  }
}

/// The sticky commitment bar: running total, then the confirm action.
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.seatCount,
    required this.fare,
    required this.loading,
    required this.onConfirm,
  });

  final int seatCount;
  final int fare;
  final bool loading;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('الإجمالي · ${formatSeats(seatCount)}',
                  style: context.text.label
                      .copyWith(color: colors.textSecondary)),
              const Spacer(),
              Text(formatPrice(fare),
                  style: context.text.h1.tabular
                      .copyWith(color: colors.textPrimary)),
            ],
          ),
        ),
        SizedBox(height: space.md),
        AppButton(
          label: 'تأكيد الحجز',
          icon: AppIcons.check,
          loading: loading,
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

/// Inline error. Seat-gone offers a back-to-results action; everything else
/// just shows the (already-Arabic) message.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, this.onBack});

  final BookingError error;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final seatGone = error.kind == BookingErrorKind.seatGone;
    // Opaque tonal fills — an alpha tint composites over whatever is behind the
    // banner and silently changes its contrast.
    final tone = seatGone ? colors.warning : colors.danger;
    final tonal = seatGone ? colors.warningTonal : colors.dangerTonal;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: tonal,
        borderRadius: context.radii.fieldLgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(seatGone ? AppIcons.warning : AppIcons.danger,
                  size: space.lg, color: tone),
              SizedBox(width: space.sm),
              Expanded(
                child: Text(error.message,
                    style: context.text.body.copyWith(color: tone)),
              ),
            ],
          ),
          if (onBack != null) ...[
            SizedBox(height: space.md),
            AppButton(
              label: 'عد إلى الرحلات',
              variant: AppButtonVariant.secondary,
              icon: AppIcons.back,
              expand: false,
              onPressed: onBack,
            ),
          ],
        ],
      ),
    );
  }
}
