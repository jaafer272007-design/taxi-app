import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../booking/booking_models.dart';
import 'seat_request_form_controller.dart';
import 'seat_request_sent_screen.dart';

/// «اطلب مقعد» — the rider asks for a seat instead of picking an existing trip.
///
/// ## The two things this screen has to get right
///
/// **The window, not a time.** Pooling works because windows overlap; a single
/// departure time would match almost nobody, and a rider whose request never
/// pooled would have no way to understand why. So the form asks for earliest
/// and latest, and says out loud that a wider window finds a car sooner.
///
/// **The price, before committing.** The corridor's suggested price is stated
/// with the total, and the one exception — a driver may later propose a raise
/// the rider can refuse for free — is written next to it rather than buried in
/// terms nobody reads. This is the only path in the app where a price can move
/// after the rider commits; hiding that would be the dark pattern.
class SeatRequestScreen extends StatefulWidget {
  const SeatRequestScreen({super.key});

  @override
  State<SeatRequestScreen> createState() => _SeatRequestScreenState();
}

class _SeatRequestScreenState extends State<SeatRequestScreen> {
  Future<void> _pickPoint({required bool isPickup}) async {
    final c = context.read<SeatRequestFormController>();
    final locationService = context.read<LocationService>();
    final geocoder = context.read<ReverseGeocoder>();

    final city = isPickup ? c.originCity : c.destCity;
    final cityName = cityArName(city);
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
      fallbackLabel: '$cityName - النقطة المحددة',
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

  Future<void> _pickDay() async {
    final c = context.read<SeatRequestFormController>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: c.day,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) c.setDay(picked);
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final c = context.read<SeatRequestFormController>();
    final picked = await showTimePicker(
      context: context,
      initialTime: isFrom ? c.from : c.to,
    );
    if (picked == null) return;
    if (isFrom) {
      // Keep the window valid as the rider edits: nudging «من» past «حتى»
      // pushes «حتى» along rather than leaving an impossible pair on screen.
      final to = c.to;
      final invalid = picked.hour * 60 + picked.minute >= to.hour * 60 + to.minute;
      c.setWindow(picked, invalid ? _plusTwoHours(picked) : to);
    } else {
      c.setWindow(c.from, picked);
    }
  }

  static TimeOfDay _plusTwoHours(TimeOfDay t) =>
      TimeOfDay(hour: (t.hour + 2) % 24, minute: t.minute);

  Future<void> _submit() async {
    final c = context.read<SeatRequestFormController>();
    final ok = await c.submit();
    if (!ok || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SeatRequestSentScreen(
          originCity: c.originCity,
          destCity: c.destCity,
          windowStart: c.windowStart,
          windowEnd: c.windowEnd,
          seatCount: c.seatCount,
          pricePerSeat: c.pricePerSeat,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeatRequestFormController>();
    final colors = context.colors;
    final space = context.space;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('اطلب مقعد')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(space.lg, space.lg, space.lg, space.xl4),
          children: [
            _RouteCard(originCity: c.originCity, destCity: c.destCity),
            SizedBox(height: space.lg),

            const _SectionLabel('متى تريد المغادرة؟'),
            SizedBox(height: space.sm),
            _WindowCard(
              day: c.day,
              from: c.from,
              to: c.to,
              onPickDay: _pickDay,
              onPickFrom: () => _pickTime(isFrom: true),
              onPickTo: () => _pickTime(isFrom: false),
            ),
            SizedBox(height: space.lg),

            const _SectionLabel('عدد المقاعد'),
            SizedBox(height: space.sm),
            AppCard(
              child: SeatCountPicker(
                value: c.seatCount,
                max: 4,
                onChanged: c.setSeatCount,
              ),
            ),
            SizedBox(height: space.lg),

            const _SectionLabel('من أين وإلى أين؟'),
            SizedBox(height: space.sm),
            AppCard(
              child: Column(
                children: [
                  _PointRow(
                    title: 'نقطة الانطلاق',
                    point: c.pickup,
                    isSet: c.pickupSet,
                    onTap: () => _pickPoint(isPickup: true),
                  ),
                  Divider(height: space.lg, color: colors.border),
                  _PointRow(
                    title: 'نقطة النزول',
                    point: c.dropoff,
                    isSet: c.dropoffSet,
                    onTap: () => _pickPoint(isPickup: false),
                  ),
                ],
              ),
            ),
            SizedBox(height: space.lg),

            _PriceCard(
              pricePerSeat: c.pricePerSeat,
              seatCount: c.seatCount,
              total: c.totalFare,
            ),
            SizedBox(height: space.md),
            const _NotABookingNote(),

            if (c.error != null) ...[
              SizedBox(height: space.lg),
              _ErrorBanner(message: c.error!),
            ],
            if (c.error == null && c.blockedReason != null) ...[
              SizedBox(height: space.md),
              Text(
                c.blockedReason!,
                style: context.text.caption.copyWith(color: colors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],

            SizedBox(height: space.lg),
            AppButton(
              label: 'أرسل الطلب',
              icon: AppIcons.seat,
              loading: c.submitting,
              onPressed: c.canSubmit ? _submit : null,
            ),
          ],
        ),
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
        style: context.text.bodyStrong.copyWith(color: context.colors.textPrimary),
      );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.originCity, required this.destCity});

  final String originCity;
  final String destCity;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(AppIcons.route, color: context.colors.primary, size: context.space.lg),
          SizedBox(width: context.space.sm),
          Expanded(
            child: Text(
              // The WORD «إلى» — the bundled Cairo has no arrow glyph.
              '${cityArName(originCity)} إلى ${cityArName(destCity)}',
              style: context.text.title,
            ),
          ),
        ],
      ),
    );
  }
}

/// Day + the earliest/latest pair, with the reason a window is asked for.
class _WindowCard extends StatelessWidget {
  const _WindowCard({
    required this.day,
    required this.from,
    required this.to,
    required this.onPickDay,
    required this.onPickFrom,
    required this.onPickTo,
  });

  final DateTime day;
  final TimeOfDay from;
  final TimeOfDay to;
  final VoidCallback onPickDay;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldRow(
            label: 'اليوم',
            value: formatDayShort(day),
            icon: AppIcons.calendar,
            onTap: onPickDay,
          ),
          Divider(height: space.lg, color: colors.border),
          Row(
            children: [
              Expanded(
                child: _FieldRow(
                  label: 'من',
                  value: formatClock(from.hour, from.minute),
                  icon: AppIcons.clock,
                  onTap: onPickFrom,
                ),
              ),
              SizedBox(width: space.md),
              Expanded(
                child: _FieldRow(
                  label: 'حتى',
                  value: formatClock(to.hour, to.minute),
                  icon: AppIcons.clock,
                  onTap: onPickTo,
                ),
              ),
            ],
          ),
          SizedBox(height: space.md),
          Text(
            // Why a window and not a time — said once, where the rider is
            // deciding, instead of leaving them to guess.
            'كلّما وسّعت المدة، زادت فرصة أن نجمعك مع ركّاب آخرين ويستلم سائق الرحلة أسرع.',
            style: context.text.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(icon, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: context.text.caption.copyWith(color: colors.textMuted)),
                    SizedBox(height: space.xs),
                    Text(value, style: context.text.bodyStrong),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                        style: context.text.caption.copyWith(color: colors.textMuted)),
                    SizedBox(height: space.xs),
                    Text(
                      hasLabel ? point.label.trim() : 'حدّد النقطة على الخريطة',
                      style: hasLabel
                          ? context.text.bodyStrong
                          : context.text.body.copyWith(color: colors.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: space.sm),
              Icon(AppIcons.chevronLeft, size: space.lg, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The price, stated before committing — including the one way it can change.
class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.pricePerSeat,
    required this.seatCount,
    required this.total,
  });

  final int pricePerSeat;
  final int seatCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('سعر المقعد', style: context.text.body),
              Text(formatPrice(pricePerSeat), style: context.text.bodyStrong),
            ],
          ),
          SizedBox(height: space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // «لـ» joins the count to the word — never a dot-like separator,
              // which fuses onto an Arabic-Indic digit and reads as a zero.
              Text('الإجمالي لـ${formatSeats(seatCount)}',
                  style: context.text.body),
              Text(formatPrice(total), style: context.text.title),
            ],
          ),
          SizedBox(height: space.md),
          Container(
            padding: EdgeInsets.all(space.md),
            decoration: BoxDecoration(
              // Opaque tonal — an alpha tint measures differently on the page
              // background than inside a card.
              color: colors.infoTonal,
              borderRadius: context.radii.cardAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.info, size: space.lg, color: colors.info),
                SizedBox(width: space.sm),
                Expanded(
                  child: Text(
                    // The exception, in plain words and up front. This is the
                    // only place in the app where a price can move after the
                    // rider commits, and burying it is what would make it a
                    // trap.
                    'هذا ما ستدفعه. إن لم يكتمل العدد قد يقترح السائق سعراً أعلى، '
                    'وعندها تقرّر أنت: الرفض بلا أي رسوم.',
                    style: context.text.caption.copyWith(color: colors.info),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A request is not a booking — said plainly, with no timeframe promised.
class _NotABookingNote extends StatelessWidget {
  const _NotABookingNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: context.radii.cardAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.clock, size: space.lg, color: colors.textSecondary),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(
              // No «قريباً», no number of days — we do not have one, and a
              // promise we cannot keep is worse than no promise.
              'هذا طلب وليس حجزاً. ننتظر ركّاباً آخرين على نفس المسار ثم سائقاً '
              'يستلم الرحلة، وسنخبرك في الحالتين: إن تأكّدت أو إن لم تتوفّر.',
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        color: colors.dangerTonal,
        borderRadius: context.radii.cardAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.warning, size: space.lg, color: colors.danger),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(message,
                style: context.text.body.copyWith(color: colors.danger)),
          ),
        ],
      ),
    );
  }
}
