import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../trip/driver_trip_models.dart';
import '../trip/trip_format.dart';
import 'earnings_controller.dart';

/// "أرباحي": the driver's cash earnings — today's total, the all-time total, and
/// a per-trip breakdown (date + amount). All figures are IQD, cash.
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
        EarningsStatus.loading =>
          Center(child: CircularProgressIndicator(color: context.colors.primary)),
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
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: controller.load,
      child: ListView(
        padding: EdgeInsets.all(space.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: _TotalCard(
                  label: 'أرباح اليوم',
                  amount: controller.todayTotal,
                ),
              ),
              SizedBox(width: space.md),
              Expanded(
                child: _TotalCard(
                  label: 'الإجمالي',
                  amount: controller.allTimeTotal,
                  highlight: true,
                ),
              ),
            ],
          ),
          SizedBox(height: space.lg),
          Text('سجل الأرباح',
              style: context.text.h2.copyWith(color: context.colors.textPrimary)),
          SizedBox(height: space.md),
          if (controller.isEmpty)
            const _NoRecords()
          else
            for (final r in controller.records) ...[
              _RecordRow(record: r),
              SizedBox(height: space.sm),
            ],
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    this.highlight = false,
  });

  final String label;
  final int amount;
  final bool highlight;

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
              Icon(AppIcons.cash, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Expanded(
                child: Text(label,
                    style: context.text.caption.copyWith(color: colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          SizedBox(height: space.sm),
          Text(formatIqd(amount),
              style: context.text.h1.tabular.copyWith(
                  color: highlight ? colors.primary : colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text('د.ع', style: context.text.caption.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final EarningsRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return AppCard(
      muted: true,
      elevated: false,
      child: Row(
        children: [
          Icon(AppIcons.cash, size: space.xl, color: colors.success),
          SizedBox(width: space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رحلة منتهية',
                    style: context.text.bodyStrong
                        .copyWith(color: colors.textPrimary)),
                SizedBox(height: space.xs),
                Text(
                  '${formatDayBaghdad(record.collectedAt)} · ${formatTime(record.collectedAt)}',
                  style: context.text.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(width: space.sm),
          Text(formatPrice(record.amount),
              style: context.text.title.tabular.copyWith(color: colors.primary)),
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
          Icon(AppIcons.wallet, size: space.xl3, color: colors.textMuted),
          SizedBox(height: space.md),
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
            Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
            SizedBox(height: space.lg),
            Text(message, style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.xl),
            AppButton(label: 'إعادة المحاولة', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
