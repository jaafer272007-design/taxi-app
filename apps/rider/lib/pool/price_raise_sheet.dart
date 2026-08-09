import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'seat_request_models.dart';

/// The driver proposes a higher price. The rider accepts or declines.
///
/// ## This is the only place in the app where a price moves after a commitment
///
/// Everything else guarantees the price you see is the price you pay. So the
/// job of this sheet is to make an exception feel like **an offer**, not a
/// trap, and every choice below is in service of that:
///
///  * **Old and new side by side, with the difference.** A single new number
///    asks the rider to do arithmetic under time pressure to find out what
///    changed — which is precisely the condition in which people agree to
///    things they did not mean to.
///  * **Neither answer is pre-selected**, and both are full-width buttons of
///    the same size. Decline is not a text link hiding under the fold.
///  * **The deadline is a plain time, not a ticking countdown.** A count-down
///    manufactures urgency the situation does not actually have; the rider
///    needs the fact, not the drumbeat.
///  * **What silence does is written down.** Not answering is a decline, and a
///    rider who puts the phone down deserves to know that is safe.
///  * **«الرفض مجاني» is stated in words**, because the fear this sheet has to
///    answer is "will refusing cost me something".
///
/// Accepting is the affirmative action, so it is the primary button — but it
/// carries no extra visual weight beyond that, and the copy never implies the
/// rider should take it.
class PriceRaiseSheet extends StatelessWidget {
  const PriceRaiseSheet({
    super.key,
    required this.request,
    required this.onRespond,
  });

  final SeatRequest request;

  /// `true` = accept. Returns a message to show on failure, null on success.
  final Future<String?> Function({required bool accept}) onRespond;

  static Future<void> show(
    BuildContext context, {
    required SeatRequest request,
    required Future<String?> Function({required bool accept}) onRespond,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PriceRaiseSheet(request: request, onRespond: onRespond),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raise = request.raise;
    if (raise == null) return const SizedBox.shrink();
    return _RaiseBody(request: request, raise: raise, onRespond: onRespond);
  }
}

class _RaiseBody extends StatefulWidget {
  const _RaiseBody({
    required this.request,
    required this.raise,
    required this.onRespond,
  });

  final SeatRequest request;
  final SeatRequestRaise raise;
  final Future<String?> Function({required bool accept}) onRespond;

  @override
  State<_RaiseBody> createState() => _RaiseBodyState();
}

class _RaiseBodyState extends State<_RaiseBody> {
  bool _busy = false;
  String? _error;

  Future<void> _respond({required bool accept}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.onRespond(accept: accept);
    if (!mounted) return;
    if (message != null) {
      setState(() {
        _busy = false;
        _error = message;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final raise = widget.raise;
    final seats = widget.request.seatCount;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: context.radii.sheetTop,
      ),
      padding: EdgeInsets.fromLTRB(space.lg, space.md, space.lg, space.lg),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: space.xl2,
                  height: space.xs,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: context.radii.chipAll,
                  ),
                ),
              ),
              SizedBox(height: space.lg),

              Text('السائق يقترح سعراً أعلى', style: context.text.title),
              SizedBox(height: space.sm),
              Text(
                'لم يكتمل عدد الركّاب على ${cityArName(widget.request.originCity)} '
                'إلى ${cityArName(widget.request.destCity)}، فاقترح السائق هذا السعر. القرار لك.',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
              SizedBox(height: space.lg),

              _PriceComparison(
                oldPrice: raise.oldPricePerSeat,
                newPrice: raise.newPricePerSeat,
                seatCount: seats,
              ),
              SizedBox(height: space.lg),

              _DeadlineNote(respondBy: raise.respondBy),
              SizedBox(height: space.md),
              _FreeToDeclineNote(),

              if (_error != null) ...[
                SizedBox(height: space.md),
                Text(
                  _error!,
                  style: context.text.caption.copyWith(color: colors.danger),
                  textAlign: TextAlign.center,
                ),
              ],

              SizedBox(height: space.lg),
              // Accept is the affirmative action so it reads as primary — but
              // decline is the same width and the same height directly under
              // it, never a link and never below the fold.
              AppButton(
                label: 'أوافق على السعر الجديد',
                loading: _busy,
                onPressed: _busy ? null : () => _respond(accept: true),
              ),
              SizedBox(height: space.sm),
              AppButton(
                label: 'أرفض وألغِ حجزي',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : () => _respond(accept: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Old and new, side by side, with what actually changed.
class _PriceComparison extends StatelessWidget {
  const _PriceComparison({
    required this.oldPrice,
    required this.newPrice,
    required this.seatCount,
  });

  final int oldPrice;
  final int newPrice;
  final int seatCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final difference = newPrice - oldPrice;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PriceBlock(
                  label: 'السعر الحالي',
                  value: formatPrice(oldPrice),
                  muted: true,
                ),
              ),
              SizedBox(width: space.md),
              Expanded(
                child: _PriceBlock(
                  label: 'السعر المقترح',
                  value: formatPrice(newPrice),
                ),
              ),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: space.md, color: colors.border),
          SizedBox(height: space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الفرق للمقعد', style: context.text.body),
              Text(formatPrice(difference), style: context.text.bodyStrong),
            ],
          ),
          if (seatCount > 1) ...[
            SizedBox(height: space.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // «لـ» binds the count to the word, so no dot-like glyph can
                // land beside an Arabic-Indic digit and read as a zero.
                Text('الإجمالي الجديد لـ${formatSeats(seatCount)}',
                    style: context.text.body),
                Text(formatPrice(newPrice * seatCount),
                    style: context.text.title),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled price.
///
/// **The current price is NOT struck through**, and that is a decision, not an
/// omission. A line through it says "this no longer applies" — but the rider
/// has not decided yet, and until they do it is the price they are owed. Ruling
/// it out on screen presumes the answer, which is the quietest kind of dark
/// pattern. It was tried, and the golden showed exactly that: the number the
/// rider is being asked to compare against was the harder of the two to read.
/// So the difference between the two blocks is weight and colour only.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: context.text.caption.copyWith(color: colors.textMuted)),
        SizedBox(height: context.space.xs),
        Text(
          value,
          style: context.text.title.copyWith(
            color: muted ? colors.textSecondary : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The deadline as a fact, and what happens if the rider says nothing.
class _DeadlineNote extends StatelessWidget {
  const _DeadlineNote({required this.respondBy});

  final DateTime respondBy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        // `warning`, not `danger`: this is a deadline, not an emergency, and
        // a red panel here would be the pressure styling we are avoiding.
        color: colors.warningTonal,
        borderRadius: context.radii.cardAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.clock, size: space.lg, color: colors.warning),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(
              // A plain clock time, not a live countdown. And silence spelled
              // out, because a rider who puts the phone down should know that
              // it is safe to.
              'مهلة الردّ حتى الساعة ${formatTime(respondBy)}. '
              'إن لم تردّ، يُعتبر ذلك رفضاً ويُلغى حجزك بلا أي رسوم.',
              style: context.text.caption.copyWith(color: colors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// The fear this sheet exists to answer: does refusing cost me anything.
class _FreeToDeclineNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AppIcons.shield, size: space.lg, color: colors.success),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(
            'الرفض مجاني تماماً: لا رسوم، ولا يُحتسب غياباً، ولا يؤثر على حسابك.',
            style: context.text.caption.copyWith(color: colors.success),
          ),
        ),
      ],
    );
  }
}
