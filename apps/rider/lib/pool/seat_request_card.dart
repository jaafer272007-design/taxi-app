import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'seat_request_models.dart';

/// One pending seat request, as it appears above the rider's bookings.
///
/// ## Why it lives in حجوزاتي and not a tab of its own
///
/// The moment a driver claims the pool, this row goes away and a **booking
/// card appears in the list directly below it** — same screen, same scroll
/// position. That is the whole transition, and it only reads as one thing
/// becoming another because they share a surface. A separate «طلباتي» tab
/// would make the same event look like something vanishing here and appearing
/// over there, which is exactly the parallel universe this design avoids.
class SeatRequestCard extends StatelessWidget {
  const SeatRequestCard({
    super.key,
    required this.request,
    this.onCancel,
    this.onRespondToRaise,
    this.busy = false,
  });

  final SeatRequest request;

  /// Null hides the action entirely — a claimed request is cancelled through
  /// the booking rules, not here.
  final VoidCallback? onCancel;

  /// Null unless there is an open raise waiting on this rider.
  final VoidCallback? onRespondToRaise;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final stage = request.stage;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // The word «إلى» — Cairo has no arrow glyph.
                  '${cityArName(request.originCity)} إلى ${cityArName(request.destCity)}',
                  style: context.text.bodyStrong,
                ),
              ),
              SizedBox(width: space.sm),
              _StageBadge(stage: stage),
            ],
          ),
          SizedBox(height: space.sm),

          // The window, as two clock runs joined by strong Arabic words. A
          // dot-like separator here would fuse onto an Arabic-Indic digit and
          // be read as an extra zero.
          _MetaRow(
            icon: AppIcons.clock,
            text:
                '${formatDayShortBaghdad(request.windowStart)} بين ${formatTime(request.windowStart)} و${formatTime(request.windowEnd)}',
          ),
          SizedBox(height: space.xs),
          _MetaRow(icon: AppIcons.seat, text: formatSeats(request.seatCount)),
          if (request.pricePerSeat != null) ...[
            SizedBox(height: space.xs),
            _MetaRow(
              icon: AppIcons.cash,
              text: 'سعر المقعد ${formatPrice(request.pricePerSeat!)}',
            ),
          ],

          SizedBox(height: space.md),
          _StageExplainer(request: request),

          if (onRespondToRaise != null) ...[
            SizedBox(height: space.md),
            AppButton(
              label: 'اطّلع على السعر الجديد',
              icon: AppIcons.cash,
              onPressed: busy ? null : onRespondToRaise,
            ),
          ],
          if (onCancel != null) ...[
            SizedBox(height: space.sm),
            AppButton(
              label: 'إلغاء الطلب',
              variant: AppButtonVariant.dangerTonal,
              expand: false,
              loading: busy,
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.stage});

  final SeatRequestStage stage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color fg, Color bg) = switch (stage) {
      SeatRequestStage.raisePending => (colors.warning, colors.warningTonal),
      SeatRequestStage.claimed => (colors.success, colors.successTonal),
      SeatRequestStage.waitingForDriver => (colors.primary, colors.primaryTonal),
      SeatRequestStage.waitingForRiders => (colors.info, colors.infoTonal),
      _ => (colors.textSecondary, colors.surfaceMuted),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        // Opaque tonal tokens only — a translucent tint composites over
        // whatever sits behind it and silently fails contrast.
        color: bg,
        borderRadius: context.radii.chipAll,
      ),
      child: Text(
        seatRequestStageLabel(stage),
        style: context.text.caption.copyWith(color: fg),
      ),
    );
  }
}

/// What the rider is actually waiting for, in a sentence.
///
/// The badge names the state; this says what it *means*. «بانتظار ركّاب آخرين»
/// on its own invites the question "how many more?", and the honest answer —
/// we cannot promise — is better said than left to be guessed at.
class _StageExplainer extends StatelessWidget {
  const _StageExplainer({required this.request});

  final SeatRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    final text = switch (request.stage) {
      SeatRequestStage.waitingForRiders =>
        'نجمعك مع ركّاب آخرين على نفس المسار في نفس الوقت. سنخبرك عندما يستلم سائق رحلتك.',
      SeatRequestStage.waitingForDriver =>
        'اكتمل العدد وظهر طلبك للسائقين. سنخبرك فور أن يستلمه أحدهم.',
      SeatRequestStage.raisePending =>
        'لم يكتمل العدد، فاقترح السائق سعراً أعلى. الرفض مجاني تماماً.',
      SeatRequestStage.claimed =>
        'صار عندك حجز مؤكد — تجده في قائمة حجوزاتك بالأسفل.',
      SeatRequestStage.declined =>
        'رفضت السعر الجديد وأُلغي حجزك بلا أي رسوم.',
      SeatRequestStage.expired =>
        'لم يستلم أحد رحلتك خلال المدة التي حدّدتها. لم تُحاسب على شيء.',
      SeatRequestStage.cancelled => 'ألغيت هذا الطلب.',
      SeatRequestStage.unknown => 'نتابع طلبك.',
    };

    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: context.radii.cardAll,
      ),
      child: Text(
        text,
        style: context.text.caption.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      children: [
        Icon(icon, size: space.lg, color: colors.textMuted),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}
