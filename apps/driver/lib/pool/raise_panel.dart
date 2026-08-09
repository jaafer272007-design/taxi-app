import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'pool_models.dart';
import 'raise_controller.dart';
import 'raise_sheet.dart';

/// Everything about the pool behind a claimed trip, on the trip's own screen.
///
/// It renders **nothing at all** for a trip the driver posted themselves — a
/// panel saying "this trip has no pool" would be noise on every ordinary trip
/// in the app. The three states it does render are:
///
///  * **an offer to raise**, when the car is not full and the rules still allow
///    it;
///  * **why not**, when they do not — a disabled control with no reason is what
///    generates support calls;
///  * **the waiting state**, once a raise is out: who accepted, who declined,
///    who has not answered, and by when.
class RaisePanel extends StatefulWidget {
  const RaisePanel({super.key});

  @override
  State<RaisePanel> createState() => _RaisePanelState();
}

class _RaisePanelState extends State<RaisePanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<RaiseController>();
      if (!c.hasLoaded) c.load();
    });
  }

  Future<void> _onPropose(RaiseController c) async {
    final pool = c.pool;
    if (pool == null) return;
    await RaiseSheet.show(context, pool: pool, onPropose: c.propose);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RaiseController>();
    final pool = c.pool;

    // Not a pooled trip, or not loaded yet: draw nothing. This panel is an
    // addition to a screen that already works without it.
    if (pool == null) return const SizedBox.shrink();

    final space = context.space;
    final raise = pool.raise;

    return Padding(
      padding: EdgeInsets.only(bottom: space.lg),
      child: raise == null
          ? _ProposeCard(pool: pool, onPropose: () => _onPropose(c))
          : _RaiseStateCard(pool: pool, raise: raise),
    );
  }
}

/// The offer — or the reason there isn't one.
class _ProposeCard extends StatelessWidget {
  const _ProposeCard({required this.pool, required this.onPropose});

  final DriverPool pool;
  final VoidCallback onPropose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.users, size: space.lg, color: colors.primary),
              SizedBox(width: space.sm),
              Expanded(
                child: Text('رحلة من تجمّع', style: context.text.bodyStrong),
              ),
            ],
          ),
          SizedBox(height: space.sm),
          Text(
            'هؤلاء الركّاب طلبوا مقاعدهم قبل أن تستلم، والسعر الذي التزموا به '
            '${formatPrice(pool.pricePerSeat)} للمقعد.',
            style: context.text.caption.copyWith(color: colors.textSecondary),
          ),

          if (pool.emptySeats > 0) ...[
            SizedBox(height: space.md),
            Container(
              padding: EdgeInsets.all(space.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: context.radii.cardAll,
              ),
              child: Text(
                'بقيت ${formatSeats(pool.emptySeats)} فارغة. يمكنك انتظار ركّاب '
                'يحجزونها بالسعر الحالي، أو تقترح سعراً أعلى على الحاليين.',
                style: context.text.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ],

          SizedBox(height: space.md),
          if (pool.canPropose)
            AppButton(
              label: 'اقترح سعراً أعلى',
              variant: AppButtonVariant.secondary,
              icon: AppIcons.cash,
              onPressed: onPropose,
            )
          else
            // The reason, not a greyed-out button. A driver who cannot act and
            // is not told why assumes the app is broken.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.info, size: space.lg, color: colors.textMuted),
                SizedBox(width: space.sm),
                Expanded(
                  child: Text(
                    pool.blockedReason ?? 'لا يمكن اقتراح رفع على هذه الرحلة.',
                    style:
                        context.text.caption.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A raise is out, or has landed. Either way this is the answer to "what is
/// happening to my trip".
class _RaiseStateCard extends StatelessWidget {
  const _RaiseStateCard({required this.pool, required this.raise});

  final DriverPool pool;
  final PoolRaise raise;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final waiting = raise.isWaiting;

    final (Color tone, Color tonal, String title) = switch ((
      waiting,
      raise.outcome
    )) {
      (true, _) => (colors.warning, colors.warningTonal, 'بانتظار ردّ الركّاب'),
      (false, RaiseOutcome.accepted) => (
          colors.success,
          colors.successTonal,
          'اكتمل الردّ — الرحلة بالسعر الجديد',
        ),
      (false, RaiseOutcome.failed) => (
          colors.danger,
          colors.dangerTonal,
          'لم يكتمل العدد — أُلغيت الرحلة',
        ),
      _ => (colors.textSecondary, colors.surfaceMuted, 'انتهى الاقتراح'),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.cash, size: space.lg, color: tone),
              SizedBox(width: space.sm),
              Expanded(child: Text(title, style: context.text.bodyStrong)),
            ],
          ),
          SizedBox(height: space.md),

          // The two prices, so the driver can see what is at stake without
          // remembering what they proposed.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'من ${formatPrice(raise.oldPricePerSeat)} إلى '
                '${formatPrice(raise.newPricePerSeat)}',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
            ],
          ),

          if (waiting) ...[
            SizedBox(height: space.md),
            Container(
              padding: EdgeInsets.all(space.md),
              decoration: BoxDecoration(
                color: tonal,
                borderRadius: context.radii.cardAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.clock, size: space.lg, color: tone),
                  SizedBox(width: space.sm),
                  Expanded(
                    child: Text(
                      // A plain clock time, and what silence means — the same
                      // fact the rider is being shown, so neither side is
                      // surprised by the outcome.
                      'المهلة حتى الساعة ${formatTime(raise.respondBy)}. '
                      'مَن لا يردّ يُحتسب رافضاً ويُطلق مقعده.',
                      style: context.text.caption.copyWith(color: tone),
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: space.md),
          _ResponseTally(raise: raise, minSeats: pool.minSeats),

          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.sm),
          for (final row in raise.responses) ...[
            _ResponseRow(row: row),
            if (row != raise.responses.last) SizedBox(height: space.xs),
          ],

          if (!waiting) ...[
            SizedBox(height: space.md),
            Container(
              padding: EdgeInsets.all(space.md),
              decoration: BoxDecoration(
                color: tonal,
                borderRadius: context.radii.cardAll,
              ),
              child: Text(
                // What the driver NOW HOLDS — the question they actually have
                // once the dust settles.
                raise.outcome == RaiseOutcome.accepted
                    ? 'تمضي الرحلة بـ${formatSeats(raise.acceptedSeats)} '
                        'بسعر ${formatPrice(raise.newPricePerSeat)} للمقعد.'
                    : 'لم يوافق ما يكفي من الركّاب، فأُلغيت الرحلة وأُطلق '
                        'الجميع. لم يُحتسب على أحد شيء.',
                style: context.text.caption.copyWith(color: tone),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Accepted / awaiting / declined as seat counts, with the viability line.
class _ResponseTally extends StatelessWidget {
  const _ResponseTally({required this.raise, required this.minSeats});

  final PoolRaise raise;
  final int minSeats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Row(
      children: [
        Expanded(
          child: _TallyCell(
            label: 'وافقوا',
            value: formatCount(raise.acceptedSeats),
            tone: colors.success,
            zero: raise.acceptedSeats == 0,
          ),
        ),
        SizedBox(width: space.sm),
        Expanded(
          child: _TallyCell(
            label: 'لم يردّوا',
            value: formatCount(raise.pendingSeats),
            tone: colors.warning,
            zero: raise.pendingSeats == 0,
          ),
        ),
        SizedBox(width: space.sm),
        Expanded(
          child: _TallyCell(
            label: 'رفضوا',
            value: formatCount(raise.declinedSeats),
            tone: colors.textSecondary,
            zero: raise.declinedSeats == 0,
          ),
        ),
      ],
    );
  }
}

class _TallyCell extends StatelessWidget {
  const _TallyCell({
    required this.label,
    required this.value,
    required this.tone,
    this.zero = false,
  });

  final String label;
  final String value;
  final Color tone;

  /// A count of nothing. Still shown — «رفضوا ٠» is reassuring, and hiding the
  /// cell would leave the driver wondering whether it is empty or missing —
  /// but drawn muted so the eye goes to the numbers that are doing something.
  final bool zero;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return Column(
      children: [
        Text(
          value,
          style: context.text.h2.tabular
              .copyWith(color: zero ? context.colors.textMuted : tone),
        ),
        SizedBox(height: space.xs),
        Text(
          label,
          style: context.text.caption.copyWith(color: context.colors.textMuted),
        ),
      ],
    );
  }
}

/// One rider's answer.
class _ResponseRow extends StatelessWidget {
  const _ResponseRow({required this.row});

  final RaiseResponseRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    final (String label, Color tone, IconData icon) = switch (row.response) {
      RaiseResponse.accepted => ('وافق', colors.success, AppIcons.success),
      RaiseResponse.declined => ('رفض', colors.textSecondary, AppIcons.close),
      RaiseResponse.awaiting => ('لم يردّ بعد', colors.warning, AppIcons.clock),
    };

    return Row(
      children: [
        Icon(icon, size: space.lg, color: tone),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(
            // «و» joins the name to the seat count without a separator that
            // could fuse onto an Arabic-Indic digit.
            '${row.riderName?.trim().isNotEmpty ?? false ? row.riderName!.trim() : 'راكب'}'
            ' — ${formatSeats(row.seatCount)}',
            style: context.text.body.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: space.sm),
        Text(
          row.released ? '$label — أُطلق' : label,
          style: context.text.caption.copyWith(color: tone),
        ),
      ],
    );
  }
}
