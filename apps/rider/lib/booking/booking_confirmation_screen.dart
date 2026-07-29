import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'booking_api.dart';
import 'my_bookings_controller.dart';
import 'my_bookings_screen.dart';

/// Success screen after a seat is reserved.
///
/// Full-bleed per the hand-off: a pine field carrying the confirmation, with the
/// recap sheet rising over it. It is a moment, not another card in a list — the
/// one screen in the flow that is allowed to fill the display.
///
/// Takes plain values (not the controller) so it outlives the booking form's
/// provider.
///
/// ## Contrast on the pine field
///
/// Hierarchy here comes from **size and weight, not opacity**. The hand-off
/// fades its supporting copy to 72% white; an alpha wash makes the measured
/// ratio depend on the blend, so everything on the field uses full `onPrimary`
/// (7.93:1 light / 7.64:1 dark) and steps down in size instead.
///
/// The hand-off also puts a saffron check in the badge. That works in light
/// (saffron on dark pine) but not in dark, where `primary` is a bright mint and
/// the saffron measures 1.15:1 — the same conflict as the route rail's ring in
/// PR 2, resolved the same way: `onPrimary` ink, distinguished by the badge
/// behind it.
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

  /// Hand-off badge diameter.
  static const double _badge = 88;

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

    return Scaffold(
      backgroundColor: colors.primary,
      body: Column(
        children: [
          // ── The moment ────────────────────────────────────────────────
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: space.xl3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: _badge,
                        height: _badge,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          // Opaque: pre-blended rather than a live alpha wash,
                          // so the badge's contrast is fixed and measurable.
                          color: Color.alphaBlend(
                            colors.onPrimary.withValues(alpha: 0.14),
                            colors.primary,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(AppIcons.check,
                            size: space.xl4, color: colors.onPrimary),
                      ),
                      SizedBox(height: space.xl),
                      Text(
                        'تم تأكيد حجزك',
                        textAlign: TextAlign.center,
                        style: context.text.h1
                            .copyWith(color: colors.onPrimary),
                      ),
                      SizedBox(height: space.md),
                      Text(
                        'أبلغنا السائق بحجزك. ستصلك رسالة واتساب قبل الانطلاق.',
                        textAlign: TextAlign.center,
                        style: context.text.body
                            .copyWith(color: colors.onPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── The recap, rising over it ─────────────────────────────────
          _RecapSheet(
            seatCount: seatCount,
            fare: fare,
            departureTime: departureTime,
            originCity: originCity,
            destCity: destCity,
            onOpenBookings: () => _openMyBookings(context),
            onHome: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }
}

class _RecapSheet extends StatelessWidget {
  const _RecapSheet({
    required this.seatCount,
    required this.fare,
    required this.departureTime,
    required this.originCity,
    required this.destCity,
    required this.onOpenBookings,
    required this.onHome,
  });

  final int seatCount;
  final int fare;
  final DateTime departureTime;
  final String? originCity;
  final String? destCity;
  final VoidCallback onOpenBookings;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: context.radii.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            space.xl,
            space.xl2,
            space.xl,
            space.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RouteRail(
                variant: RouteRailVariant.compact,
                origin: _EndpointRow(
                  city: originCity,
                  trailing: Text(
                    formatTime(departureTime),
                    style: context.text.h2.tabular
                        .copyWith(color: colors.textPrimary),
                  ),
                ),
                destination: _EndpointRow(
                  city: destCity,
                  trailing: Text(
                    formatDayShortBaghdad(departureTime),
                    style: context.text.caption
                        .copyWith(color: colors.textMuted),
                  ),
                ),
              ),
              SizedBox(height: space.lg),
              Divider(height: 1, color: colors.border),
              SizedBox(height: space.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${formatSeats(seatCount)} · نقداً',
                      style: context.text.body
                          .copyWith(color: colors.textSecondary)),
                  const Spacer(),
                  Text(formatPrice(fare),
                      style: context.text.h1.tabular
                          .copyWith(color: colors.primary)),
                ],
              ),
              SizedBox(height: space.xl),
              AppButton(
                label: 'عرض حجوزاتي',
                icon: AppIcons.seat,
                onPressed: onOpenBookings,
              ),
              SizedBox(height: space.sm),
              AppButton(
                label: 'العودة للرئيسية',
                variant: AppButtonVariant.ghost,
                onPressed: onHome,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A city on the recap rail, with its time/date on the trailing edge.
class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.city, required this.trailing});

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
            city == null ? '—' : cityArName(city!),
            style: context.text.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing,
      ],
    );
  }
}
