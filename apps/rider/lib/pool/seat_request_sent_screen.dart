import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// «أرسلنا طلبك» — the honest confirmation.
///
/// It confirms what was *recorded*, not what will happen. A rider who reads
/// this and expects a car is a rider we misled; a rider who reads it and knows
/// they will be told either way is one who can get on with their day.
///
/// No timeframe appears anywhere here, and `seat_request_test.dart` asserts the
/// absence rather than trusting the copy to stay honest.
class SeatRequestSentScreen extends StatelessWidget {
  const SeatRequestSentScreen({
    super.key,
    required this.originCity,
    required this.destCity,
    required this.windowStart,
    required this.windowEnd,
    required this.seatCount,
    required this.pricePerSeat,
    this.onDone,
  });

  final String originCity;
  final String destCity;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int seatCount;
  final int pricePerSeat;

  /// What «تم» does. Defaults to popping back to wherever the rider came from.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('طلبك')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(space.lg),
          children: [
            SizedBox(height: space.xl),
            Center(
              child: Container(
                width: space.xl4 + space.xl2,
                height: space.xl4 + space.xl2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.successTonal,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.success,
                    color: colors.success, size: space.xl2),
              ),
            ),
            SizedBox(height: space.lg),
            Text(
              'أرسلنا طلبك',
              style: context.text.h2,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: space.sm),
            Text(
              'سنخبرك عندما يستلم سائق رحلتك — وأيضاً إن لم تتوفّر.',
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: space.xl),

            AppCard(
              child: Column(
                children: [
                  _Row(
                    label: 'المسار',
                    value: '${cityArName(originCity)} إلى ${cityArName(destCity)}',
                  ),
                  Divider(height: space.lg, color: colors.border),
                  _Row(
                    label: 'المغادرة',
                    // Two clock runs joined by a strong Arabic word, never a
                    // dot-like separator beside an Arabic-Indic digit.
                    value:
                        '${formatDayShortBaghdad(windowStart)} بين ${formatTime(windowStart)} و${formatTime(windowEnd)}',
                  ),
                  Divider(height: space.lg, color: colors.border),
                  _Row(label: 'المقاعد', value: formatSeats(seatCount)),
                  Divider(height: space.lg, color: colors.border),
                  _Row(
                    label: 'سعر المقعد',
                    value: formatPrice(pricePerSeat),
                    strong: true,
                  ),
                ],
              ),
            ),
            SizedBox(height: space.lg),

            Container(
              padding: EdgeInsets.all(space.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: context.radii.cardAll,
              ),
              child: Text(
                'تتابع طلبك من «حجوزاتي». يمكنك إلغاؤه في أي وقت قبل أن يستلمه سائق.',
                style: context.text.caption.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(height: space.xl),

            AppButton(
              label: 'تم',
              onPressed: onDone ?? () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: context.text.body.copyWith(color: context.colors.textSecondary)),
        SizedBox(width: context.space.md),
        Flexible(
          child: Text(
            value,
            style: strong ? context.text.title : context.text.bodyStrong,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
