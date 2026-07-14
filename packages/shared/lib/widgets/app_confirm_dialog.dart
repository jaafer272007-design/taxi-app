import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';

/// A themed confirm dialog: a title, a message, and two token-driven buttons.
/// Its buttons pop the dialog route with `true` (confirm) / `false` (cancel), so
/// [showAppConfirmDialog] resolves to the user's choice.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'تراجع',
    this.confirmVariant = AppButtonVariant.primary,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final AppButtonVariant confirmVariant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(title,
          style: context.text.title.copyWith(color: colors.textPrimary)),
      content: Text(message,
          style: context.text.body.copyWith(color: colors.textSecondary)),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.ghost,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: confirmVariant,
          expand: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Show an [AppConfirmDialog] and resolve to the user's choice (`false` if
/// dismissed by tapping outside).
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'تراجع',
  AppButtonVariant confirmVariant = AppButtonVariant.primary,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AppConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmVariant: confirmVariant,
    ),
  );
  return result ?? false;
}
