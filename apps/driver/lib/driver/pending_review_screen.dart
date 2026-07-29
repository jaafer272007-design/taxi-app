import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'documents_screen.dart';
import 'driver_controller.dart';
import 'driver_models.dart';

/// Status screen for a registered driver who cannot post trips yet: PENDING
/// (reassuring, awaiting review), REJECTED (reason + re-upload), or SUSPENDED.
///
/// A driver waiting on approval has one real question — *where am I, and what
/// happens next* — so a pending account gets an explicit three-step tracker
/// rather than a single spinner-ish "قيد المراجعة". Waiting is tolerable;
/// waiting without knowing what you are waiting for is not.
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

    // Opaque tonal fills, never `tone.withValues(alpha: …)`: this badge sits on
    // the page background, and a live tint would measure differently the moment
    // it moved onto a card.
    final (IconData icon, Color tone, Color tonal, String title,
        String subtitle) = switch (status) {
      DriverStatus.rejected => (
        AppIcons.danger,
        colors.danger,
        colors.dangerTonal,
        'تم رفض طلبك',
        'راجع السبب أدناه، صحّح المطلوب، وأعد رفع مستمسكاتك.',
      ),
      DriverStatus.suspended => (
        AppIcons.warning,
        colors.warning,
        colors.warningTonal,
        'حسابك موقوف مؤقتاً',
        'تواصل مع الدعم لإعادة تفعيل حسابك.',
      ),
      _ => (
        AppIcons.clock,
        colors.info,
        colors.infoTonal,
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
                color: tonal,
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
            SizedBox(height: space.xl2),
            const _ReviewSteps(),
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
      return const AppBadge(label: 'لم يُرفع', tone: AppBadgeTone.neutral);
    }
    final (String label, AppBadgeTone tone) = switch (doc.status) {
      DocStatus.approved => ('مقبول', AppBadgeTone.success),
      DocStatus.rejected => ('مرفوض', AppBadgeTone.danger),
      _ => ('قيد المراجعة', AppBadgeTone.warning),
    };
    return AppBadge(label: label, tone: tone);
  }
}

/// The approval path, drawn as three steps so the wait has a shape.
///
/// Only the middle step is live; the app cannot know how far along the admin
/// is, so it does not pretend to — the tracker says *where in the process the
/// driver is*, not how long is left.
class _ReviewSteps extends StatelessWidget {
  const _ReviewSteps();

  static const _steps = [
    (_StepState.done, 'أرسلت مستمسكاتك', 'استلمنا الملفات كاملة.'),
    (_StepState.current, 'قيد مراجعة الإدارة', 'نتحقق من المستمسكات والمركبة.'),
    (_StepState.upcoming, 'يمكنك نشر الرحلات', 'سيصلك إشعار فور الاعتماد.'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _steps.length; i++)
            _StepRow(
              state: _steps[i].$1,
              title: _steps[i].$2,
              subtitle: _steps[i].$3,
              last: i == _steps.length - 1,
            ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.state,
    required this.title,
    required this.subtitle,
    required this.last,
  });

  final _StepState state;
  final String title;
  final String subtitle;
  final bool last;

  /// Marker diameter and the run of the connector under it.
  static const double _marker = 28;
  static const double _run = 22;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    final (Color fill, Color ink, IconData? icon) = switch (state) {
      _StepState.done => (colors.successTonal, colors.success, AppIcons.check),
      _StepState.current => (colors.primaryTonal, colors.primary, AppIcons.clock),
      _StepState.upcoming => (colors.surfaceMuted, colors.textMuted, null),
    };
    final titleInk =
        state == _StepState.upcoming ? colors.textMuted : colors.textPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: _marker,
              height: _marker,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: icon == null
                  ? Container(
                      width: space.sm,
                      height: space.sm,
                      decoration:
                          BoxDecoration(color: ink, shape: BoxShape.circle),
                    )
                  : Icon(icon, size: space.md, color: ink),
            ),
            // Decorative connector — redundant with the markers it joins.
            if (!last)
              Container(width: 2, height: _run, color: colors.border),
          ],
        ),
        SizedBox(width: space.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: context.text.bodyStrong.copyWith(color: titleInk)),
                SizedBox(height: space.xs),
                Text(subtitle,
                    style: context.text.caption
                        .copyWith(color: colors.textMuted)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
