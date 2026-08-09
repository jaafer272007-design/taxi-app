import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'pool_models.dart';
import 'raise_projection.dart';

/// Propose a higher price to the riders already holding seats.
///
/// ## The driver is trading certainty for money, and it is not obviously a good
/// trade
///
/// Every rider may decline, and a decliner is **released** — so a higher price
/// per seat can mean less money in total and fewer passengers. A screen that
/// showed only the optimistic figure would be selling the driver something.
/// So this one states, before the proposal goes out:
///
///  * that it is **one proposal only** — there is no second try;
///  * the **cap**, which is the admin's number and not negotiable;
///  * the **deadline** for proposing, and how long riders then have;
///  * that declining is free for the rider and costs the driver the seat;
///  * and the arithmetic in three lines: now, if all accept, and if only the
///    minimum accepts.
///
/// The last one is the point. `raise_projection.dart` computes it and is unit
/// tested, because it is the number the whole decision rests on.
class RaiseSheet extends StatefulWidget {
  const RaiseSheet({super.key, required this.pool, required this.onPropose});

  final DriverPool pool;

  /// Returns null on success, else a message to show.
  final Future<String?> Function(int newPricePerSeat) onPropose;

  static Future<void> show(
    BuildContext context, {
    required DriverPool pool,
    required Future<String?> Function(int) onPropose,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RaiseSheet(pool: pool, onPropose: onPropose),
    );
  }

  @override
  State<RaiseSheet> createState() => _RaiseSheetState();
}

class _RaiseSheetState extends State<RaiseSheet> {
  late int _price;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Opens one step above the current price, not at the cap: the sheet must
    // not read as a suggestion to charge the maximum.
    _price = _clamp(widget.pool.pricePerSeat + _step);
  }

  /// 500 IQD — the smallest note anyone in Iraq actually settles with.
  static const int _step = 500;

  int _clamp(int value) =>
      value.clamp(widget.pool.pricePerSeat + _step, widget.pool.maxPricePerSeat);

  bool get _canIncrease => _price + _step <= widget.pool.maxPricePerSeat;
  bool get _canDecrease => _price - _step > widget.pool.pricePerSeat;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.onPropose(_price);
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
    final pool = widget.pool;
    final projection = RaiseProjection(
      seatsTaken: pool.seatsTaken,
      currentPrice: pool.pricePerSeat,
      newPrice: _price,
      minSeats: pool.minSeats,
    );

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

              Text('اقترح سعراً أعلى', style: context.text.title),
              SizedBox(height: space.sm),
              Text(
                'يذهب الاقتراح إلى الركّاب الذين حجزوا سلفاً. لكلٍّ منهم أن '
                'يوافق أو يرفض، ومن يرفض يخرج من الرحلة بلا رسوم.',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
              SizedBox(height: space.lg),

              _PriceStepper(
                price: _price,
                currentPrice: pool.pricePerSeat,
                maxPrice: pool.maxPricePerSeat,
                onDecrease:
                    _canDecrease ? () => setState(() => _price -= _step) : null,
                onIncrease:
                    _canIncrease ? () => setState(() => _price += _step) : null,
              ),
              SizedBox(height: space.lg),

              _Consequence(projection: projection, pool: pool),
              SizedBox(height: space.md),
              _Rules(pool: pool),

              if (_error != null) ...[
                SizedBox(height: space.md),
                Container(
                  padding: EdgeInsets.all(space.md),
                  decoration: BoxDecoration(
                    color: colors.dangerTonal,
                    borderRadius: context.radii.cardAll,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.warning,
                          size: space.lg, color: colors.danger),
                      SizedBox(width: space.sm),
                      Expanded(
                        child: Text(
                          // The server's own sentence: every refusal here is
                          // specific (over the cap, already proposed, past the
                          // deadline, trip full) and each one tells the driver
                          // something different to do.
                          _error!,
                          style: context.text.body
                              .copyWith(color: colors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: space.lg),
              AppButton(
                label: 'أرسل الاقتراح',
                icon: AppIcons.cash,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
              SizedBox(height: space.sm),
              AppButton(
                label: 'تراجع',
                variant: AppButtonVariant.ghost,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The number, with its bounds visible.
class _PriceStepper extends StatelessWidget {
  const _PriceStepper({
    required this.price,
    required this.currentPrice,
    required this.maxPrice,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int price;
  final int currentPrice;
  final int maxPrice;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Column(
      children: [
        Row(
          children: [
            _StepButton(
              icon: AppIcons.minus,
              onPressed: onDecrease,
              semanticLabel: 'إنقاص السعر',
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    formatPrice(price),
                    style: context.text.h1.tabular
                        .copyWith(color: colors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: space.xs),
                  Text(
                    'للمقعد',
                    style:
                        context.text.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: AppIcons.plus,
              onPressed: onIncrease,
              semanticLabel: 'زيادة السعر',
            ),
          ],
        ),
        SizedBox(height: space.sm),
        Text(
          // Two digit runs joined by an Arabic word and an en dash between
          // NUMBERS — safe, because both sides of the dash are digits and stay
          // in one directional run.
          'السعر الحالي ${formatPrice(currentPrice)} والحد الأعلى للممر '
          '${formatPrice(maxPrice)}',
          style: context.text.caption.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          // 48 keeps the tap target above the platform minimum even though the
          // glyph inside is small.
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: Icon(
            icon,
            color: enabled ? colors.textPrimary : colors.textMuted,
            size: context.space.lg,
          ),
        ),
      ),
    );
  }
}

/// What this actually earns, in the three ways it can land.
class _Consequence extends StatelessWidget {
  const _Consequence({required this.projection, required this.pool});

  final RaiseProjection projection;
  final DriverPool pool;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AppCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ماذا يعني هذا لك', style: context.text.bodyStrong),
          SizedBox(height: space.md),
          _Line(
            label: 'الآن بـ${formatSeats(projection.seatsTaken)}',
            value: formatPrice(projection.takeNow),
          ),
          SizedBox(height: space.sm),
          _Line(
            label: 'لو وافق الجميع',
            value: formatPrice(projection.takeIfAllAccept),
            tone: colors.success,
          ),
          SizedBox(height: space.sm),
          _Line(
            // The case that decides whether this is wise, given equal weight
            // with the optimistic one rather than hidden in a footnote.
            label: 'لو وافق ${formatSeats(pool.minSeats)} فقط',
            value: formatPrice(projection.takeIfMinimumAccepts),
            tone: projection.minimumIsWorseThanNow
                ? colors.danger
                : colors.textSecondary,
          ),
          SizedBox(height: space.md),
          Container(
            padding: EdgeInsets.all(space.md),
            decoration: BoxDecoration(
              color: projection.anyDeclineEndsTrip
                  ? colors.dangerTonal
                  : colors.surfaceMuted,
              borderRadius: context.radii.cardAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  projection.anyDeclineEndsTrip
                      ? AppIcons.warning
                      : AppIcons.info,
                  size: space.lg,
                  color: projection.anyDeclineEndsTrip
                      ? colors.danger
                      : colors.textSecondary,
                ),
                SizedBox(width: space.sm),
                Expanded(
                  child: Text(
                    projection.anyDeclineEndsTrip
                        // With exactly the minimum on board, one refusal ends
                        // the trip for everyone — a different risk from
                        // earning less, and it deserves a different sentence.
                        ? 'عندك الحد الأدنى بالضبط: لو رفض راكب واحد، تُلغى '
                            'الرحلة كلها ويُطلق الجميع.'
                        : projection.minimumIsWorseThanNow
                            ? 'لو رفض بعضهم قد تنتهي بمال أقلّ مما بيدك الآن، '
                                'ومقاعد فارغة.'
                            : 'لو رفض بعضهم تمضي الرحلة بمن وافق، ما دام العدد '
                                'لا ينزل تحت ${formatSeats(pool.minSeats)}.',
                    style: context.text.caption.copyWith(
                      color: projection.anyDeclineEndsTrip
                          ? colors.danger
                          : colors.textSecondary,
                    ),
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

/// The four rules, stated before the driver commits rather than discovered by
/// being refused.
class _Rules extends StatelessWidget {
  const _Rules({required this.pool});

  final DriverPool pool;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        color: colors.infoTonal,
        borderRadius: context.radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Rule(text: 'اقتراح واحد فقط لكل رحلة — لا يمكن تعديله ولا تكراره.'),
          SizedBox(height: space.xs),
          _Rule(
            text: 'لا يتجاوز الحد الأعلى للممر '
                '(${formatPrice(pool.maxPricePerSeat)}).',
          ),
          SizedBox(height: space.xs),
          _Rule(
            text: 'آخر موعد للاقتراح الساعة '
                '${formatTime(pool.raiseDeadline)}، وللركّاب '
                '${formatMinutes(pool.responseMinutes)} للردّ.',
          ),
          SizedBox(height: space.xs),
          const _Rule(text: 'من لا يردّ يُحتسب رافضاً ويُطلق مقعده.'),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AppIcons.check, size: space.md, color: colors.info),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.caption.copyWith(color: colors.info),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: context.text.body.copyWith(
              color: tone ?? context.colors.textSecondary,
            ),
          ),
        ),
        SizedBox(width: context.space.sm),
        Text(
          value,
          style: context.text.bodyStrong.tabular
              .copyWith(color: tone ?? context.colors.textPrimary),
        ),
      ],
    );
  }
}
