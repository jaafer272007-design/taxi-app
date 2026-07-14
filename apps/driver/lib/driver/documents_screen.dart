import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'driver_controller.dart';
import 'driver_models.dart';

/// Upload the three required verification documents, each with its review status.
/// Used both as an onboarding step and (re-)opened from the rejected screen.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  Future<void> _pick(BuildContext context, DriverController c, DocType type) async {
    final err = await c.pickAndUploadDocument(type);
    if (err == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final profile = c.profile;
    final space = context.space;

    return AppScaffold(
      title: 'المستمسكات',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.md),
          Text('ارفع مستمسكاتك',
              style: context.text.h2.copyWith(color: context.colors.textPrimary)),
          SizedBox(height: space.xs),
          Text('صورة واضحة لكل مستند (صورة أو PDF، حتى 5 ميغابايت).',
              style: context.text.body.copyWith(color: context.colors.textSecondary)),
          SizedBox(height: space.lg),
          for (final type in kRequiredDocs) ...[
            _DocRow(
              type: type,
              document: profile?.documentFor(type),
              uploading: c.isUploading(type),
              onPick: () => _pick(context, c, type),
            ),
            SizedBox(height: space.md),
          ],
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.type,
    required this.document,
    required this.uploading,
    required this.onPick,
  });

  final DocType type;
  final DriverDocument? document;
  final bool uploading;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final uploaded = document != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.document, size: space.xl, color: colors.textMuted),
              SizedBox(width: space.md),
              Expanded(
                child: Text(type.labelAr,
                    style: context.text.bodyStrong.copyWith(color: colors.textPrimary)),
              ),
              _statusPill(document?.status, uploaded),
            ],
          ),
          SizedBox(height: space.md),
          AppButton(
            label: uploaded ? 'إعادة الرفع' : 'رفع الصورة',
            icon: AppIcons.upload,
            variant: uploaded ? AppButtonVariant.secondary : AppButtonVariant.primary,
            size: AppButtonSize.small,
            loading: uploading,
            onPressed: uploading ? null : onPick,
          ),
        ],
      ),
    );
  }

  Widget _statusPill(DocStatus? status, bool uploaded) {
    if (!uploaded) {
      return const AppPill(label: 'لم يُرفع', tone: AppBadgeTone.neutral);
    }
    final (String label, AppBadgeTone tone, IconData icon) = switch (status) {
      DocStatus.approved => ('مقبول', AppBadgeTone.success, AppIcons.success),
      DocStatus.rejected => ('مرفوض', AppBadgeTone.danger, AppIcons.close),
      _ => ('قيد المراجعة', AppBadgeTone.warning, AppIcons.clock),
    };
    return AppPill(label: label, tone: tone, icon: icon);
  }
}
