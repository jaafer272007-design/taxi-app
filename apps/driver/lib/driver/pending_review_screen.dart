import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'documents_screen.dart';
import 'driver_controller.dart';
import 'driver_models.dart';

/// Status screen for a registered driver who cannot post trips yet: PENDING
/// (reassuring, awaiting review), REJECTED (reason + re-upload), or SUSPENDED.
class PendingReviewScreen extends StatelessWidget {
  const PendingReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final colors = context.colors;
    final space = context.space;
    final status = c.status;
    final rejected = status == DriverStatus.rejected;
    final reason = c.profile?.rejectionReason;

    final (IconData icon, Color tone, String title, String subtitle) =
        switch (status) {
      DriverStatus.rejected => (
        AppIcons.danger,
        colors.danger,
        'تم رفض طلبك',
        'راجع السبب أدناه، صحّح المطلوب، وأعد رفع مستمسكاتك.',
      ),
      DriverStatus.suspended => (
        AppIcons.warning,
        colors.warning,
        'حسابك موقوف مؤقتاً',
        'تواصل مع الدعم لإعادة تفعيل حسابك.',
      ),
      _ => (
        AppIcons.clock,
        colors.info,
        'طلبك قيد المراجعة',
        'نراجع مستمسكاتك وسنعلمك عند الاعتماد. لا يمكنك إعلان رحلات حتى يُعتمد حسابك.',
      ),
    };

    return AppScaffold(
      title: 'حالة الطلب',
      scrollable: true,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rejected)
            AppButton(
              label: 'أعد رفع المستمسكات',
              icon: AppIcons.upload,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DocumentsScreen()),
              ),
            ),
          if (rejected) SizedBox(height: space.sm),
          AppButton(
            label: 'تحديث الحالة',
            icon: AppIcons.route,
            variant: rejected ? AppButtonVariant.ghost : AppButtonVariant.primary,
            onPressed: () => c.load(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: space.xl2),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: space.xl4 + space.xl3, // 72
              height: space.xl4 + space.xl3,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tone, size: space.xl3),
            ),
          ),
          SizedBox(height: space.lg),
          Text(title,
              style: context.text.h1.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center),
          SizedBox(height: space.sm),
          Text(subtitle,
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center),
          if (rejected && reason != null && reason.trim().isNotEmpty) ...[
            SizedBox(height: space.xl),
            DriverBanner(
              message: 'سبب الرفض: $reason',
              tone: BannerTone.danger,
            ),
          ],
          if (!rejected) ...[
            SizedBox(height: space.xl),
            _DocsSummary(profile: c.profile),
          ],
        ],
      ),
    );
  }
}

/// Compact list of the submitted documents + their review status.
class _DocsSummary extends StatelessWidget {
  const _DocsSummary({required this.profile});

  final DriverProfile? profile;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('مستمسكاتك',
              style: context.text.bodyStrong.copyWith(color: colors.textPrimary)),
          SizedBox(height: space.md),
          for (final type in kRequiredDocs) ...[
            Row(
              children: [
                Icon(AppIcons.document, size: space.lg, color: colors.textMuted),
                SizedBox(width: space.sm),
                Expanded(
                  child: Text(type.labelAr,
                      style: context.text.body.copyWith(color: colors.textSecondary)),
                ),
                _docPill(context, profile?.documentFor(type)),
              ],
            ),
            if (type != kRequiredDocs.last) SizedBox(height: space.md),
          ],
        ],
      ),
    );
  }

  Widget _docPill(BuildContext context, DriverDocument? doc) {
    if (doc == null) {
      return const AppPill(label: 'لم يُرفع', tone: AppBadgeTone.neutral);
    }
    final (String label, AppBadgeTone tone) = switch (doc.status) {
      DocStatus.approved => ('مقبول', AppBadgeTone.success),
      DocStatus.rejected => ('مرفوض', AppBadgeTone.danger),
      _ => ('قيد المراجعة', AppBadgeTone.warning),
    };
    return AppPill(label: label, tone: tone);
  }
}
