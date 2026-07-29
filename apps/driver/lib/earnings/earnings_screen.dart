import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../trip/driver_trip_models.dart';
import 'earnings_controller.dart';

/// "أرباحي": the driver's cash earnings — today's take on a pine field, the
/// all-time total under it, and a ledger grouped by Baghdad day.
///
/// This is the screen a driver opens every evening, and the one that decides
/// whether they believe the app about their money. Two rules follow from that:
///
/// 1. **Every number reconciles with the rows beneath it.** A day header's
///    subtotal is summed from the rows printed under it (see
///    `EarningsController._groupByDay`), never read from a separate field, so a
///    driver can add up the column and land on the same figure.
/// 2. **No total appears without its denominator.** "٩٦٬٠٠٠" alone invites the
///    question "from how many trips?"; the trip count sits with each total.
///
/// The hand-off puts today and the all-time total side by side as two equal
/// cards. Split across a 390dp phone that leaves each figure ~140dp, which
/// truncates a seven-digit dinar amount — and it gives equal weight to the
/// number checked daily and the one checked monthly. They are stacked instead:
/// today full-width on the pine field, all-time as a quieter strip below it.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<EarningsController>();
      if (!c.hasLoaded) c.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EarningsController>();

    return AppScaffold(
      title: 'أرباحي',
      padded: false,
      body: switch (c.status) {
        EarningsStatus.loading => Center(
            child: CircularProgressIndicator(color: context.colors.primary),
          ),
        EarningsStatus.error =>
          _ErrorView(message: c.error ?? 'حدث خطأ.', onRetry: c.load),
        EarningsStatus.loaded => _Loaded(controller: c),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.controller});

  final EarningsController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final days = controller.days;

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: controller.load,
      child: ListView(
        padding: EdgeInsets.all(space.lg),
        children: [
          _TodayCard(
            amount: controller.todayTotal,
            trips: controller.todayTripCount,
          ),
          SizedBox(height: space.md),
          _AllTimeStrip(
            amount: controller.allTimeTotal,
            trips: controller.tripCount,
          ),
          SizedBox(height: space.xl),
          Text(
            'سجل الأرباح',
            style: context.text.h2.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: space.md),
          if (days.isEmpty)
            const _NoRecords()
          else
            for (final d in days) ...[
              _DaySection(day: d),
              SizedBox(height: space.lg),
            ],
          const _CashNote(),
        ],
      ),
    );
  }
}

/// Today's take, on the pine field. The one number the screen exists for, so it
/// gets the full width and the `display` size.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.amount, required this.trips});

  final int amount;
  final int trips;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final ink = colors.onPrimary;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.xl),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: context.radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.wallet, size: space.lg, color: ink),
              SizedBox(width: space.sm),
              Text('أرباح اليوم',
                  style: context.text.label.copyWith(color: ink)),
            ],
          ),
          SizedBox(height: space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  formatIqd(amount),
                  style: context.text.display.tabular.copyWith(color: ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: space.sm),
              Text(iqdSuffix, style: context.text.title.copyWith(color: ink)),
            ],
          ),
          SizedBox(height: space.md),
          // The denominator. A total with no trip count is a number a driver
          // has no way to check.
          OnPrimaryChip(
            label: trips > 0 ? '${formatTrips(trips)} · نقداً' : 'نقداً',
            icon: AppIcons.car,
          ),
        ],
      ),
    );
  }
}

/// The all-time total — checked occasionally, so it reads as a quiet strip
/// rather than competing with today.
class _AllTimeStrip extends StatelessWidget {
  const _AllTimeStrip({required this.amount, required this.trips});

  final int amount;
  final int trips;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('الإجمالي منذ البداية',
                    style: context.text.label
                        .copyWith(color: colors.textSecondary)),
                SizedBox(height: space.xs),
                Text(formatTrips(trips),
                    style:
                        context.text.caption.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
          SizedBox(width: space.sm),
          Text(
            formatPrice(amount),
            style: context.text.h1.tabular.copyWith(color: colors.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One Baghdad day of the ledger: a header carrying the date and the day's
/// subtotal, then the day's rows in a single grouped card.
///
/// Dates here are absolute (`٢٠ تموز`), never "اليوم" / "أمس" — a driver
/// reconciling cash is matching against a calendar, and a relative label also
/// makes the screen's own screenshots change meaning overnight.
class _DaySection extends StatelessWidget {
  const _DaySection({required this.day});

  final EarningsDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final rows = day.records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatDayShort(day.date),
                  style:
                      context.text.label.copyWith(color: colors.textSecondary)),
              const Spacer(),
              Text(
                formatPrice(day.total),
                style: context.text.bodyStrong.tabular
                    .copyWith(color: colors.primary),
              ),
            ],
          ),
        ),
        SizedBox(height: space.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsetsDirectional.only(start: space.xl4),
                    child: Divider(height: 1, color: colors.border),
                  ),
                _LedgerRow(record: rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single collection: when it was taken and how much.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.record});

  final EarningsRecord record;

  /// Diameter of the leading marker.
  static const double _marker = 36;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Padding(
      padding: EdgeInsets.all(space.lg),
      child: Row(
        children: [
          Container(
            width: _marker,
            height: _marker,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Opaque tonal — this row sits on a card, but the same marker
              // appears on the muted surface elsewhere.
              color: colors.successTonal,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.cash, size: space.lg, color: colors.success),
          ),
          SizedBox(width: space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('نقد محصّل',
                    style: context.text.bodyStrong
                        .copyWith(color: colors.textPrimary)),
                SizedBox(height: space.xs),
                Text(
                  formatTime(record.collectedAt),
                  style: context.text.caption.tabular
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(width: space.sm),
          Text(
            formatPrice(record.amount),
            style: context.text.title.tabular
                .copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Says out loud what the ledger is and is not. Phase 1 is cash-only; a driver
/// should never be left wondering whether the app is holding money for them.
class _CashNote extends StatelessWidget {
  const _CashNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: space.lg, color: colors.textMuted),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(
              'كل المبالغ نقدية وتُحصّل من الركّاب مباشرة. تُسجَّل الرحلة هنا '
              'فور إتمامها — التطبيق لا يحتفظ بأي مبلغ لك.',
              style: context.text.caption.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoRecords extends StatelessWidget {
  const _NoRecords();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space.xl2),
      child: Column(
        children: [
          Container(
            width: space.xl4 + space.xl2,
            height: space.xl4 + space.xl2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryTonal,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.wallet, size: space.xl2, color: colors.primary),
          ),
          SizedBox(height: space.lg),
          Text('لا توجد أرباح بعد',
              style: context.text.title, textAlign: TextAlign.center),
          SizedBox(height: space.sm),
          Text('ستظهر أرباحك هنا بعد إتمام أول رحلة.',
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center),
        ],
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
                  Icon(AppIcons.warning, size: space.xl2, color: colors.danger),
            ),
            SizedBox(height: space.lg),
            Text(message,
                style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.xl),
            AppButton(
                label: 'إعادة المحاولة', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
