import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_user.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_avatar.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/app_text_field.dart';

/// The shared Settings screen, reused by the rider and driver apps. Reads the
/// app-wide [ThemeController] + [AuthController] from the tree; the app supplies
/// its version string and its own [onLogout] action (its root router then shows
/// that app's login).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.appVersion,
    required this.onLogout,
  });

  /// Shown in the About section (e.g. "0.1.0").
  final String appVersion;

  /// App-provided logout action; clears the session so the router shows login.
  final Future<void> Function() onLogout;

  void _editName(BuildContext context) {
    final name = context.read<AuthController>().user?.name ?? '';
    showDialog<void>(
      context: context,
      builder: (_) => _EditNameDialog(initialName: name),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'تسجيل الخروج؟',
      message: 'سيتم إنهاء جلستك على هذا الجهاز. يمكنك الدخول مجدداً في أي وقت.',
      confirmLabel: 'تسجيل الخروج',
      confirmVariant: AppButtonVariant.danger,
    );
    if (!ok) return;
    await onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final user = context.watch<AuthController>().user;

    return AppScaffold(
      title: 'الإعدادات',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(label: 'الحساب'),
          SizedBox(height: space.sm),
          _AccountCard(user: user, onEditName: () => _editName(context)),
          SizedBox(height: space.xl),
          const _SectionHeader(label: 'المظهر'),
          SizedBox(height: space.sm),
          const _ThemeSelector(),
          SizedBox(height: space.xl),
          const _SectionHeader(label: 'حول التطبيق'),
          SizedBox(height: space.sm),
          _AboutCard(version: appVersion),
          SizedBox(height: space.xl2),
          AppButton(
            label: 'تسجيل الخروج',
            variant: AppButtonVariant.dangerTonal,
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: context.text.label.copyWith(color: context.colors.textMuted),
      );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.onEditName});

  final AuthUser? user;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final hasName = user?.name?.trim().isNotEmpty ?? false;
    final name = hasName ? user!.name!.trim() : 'بدون اسم';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: name, size: space.xl3),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: context.text.title
                            .copyWith(color: colors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: space.xs),
                    // Phone is a +country number → force LTR so it reads correctly.
                    Text(
                      user?.phone ?? '',
                      textDirection: TextDirection.ltr,
                      style: context.text.body.tabular
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: 'تعديل الاسم',
              icon: AppIcons.user,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onEditName,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return AppCard(
      child: AppSegmentedControl<ThemeMode>(
        value: mode,
        onChanged: (m) => context.read<ThemeController>().setMode(m),
        segments: const [
          AppSegment(value: ThemeMode.light, label: 'فاتح'),
          AppSegment(value: ThemeMode.dark, label: 'داكن'),
          AppSegment(value: ThemeMode.system, label: 'حسب النظام'),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return AppCard(
      muted: true,
      elevated: false,
      child: Row(
        children: [
          Icon(AppIcons.info, size: space.xl, color: colors.textMuted),
          SizedBox(width: space.md),
          Expanded(
            child: Text('تكسي مشترك',
                style: context.text.bodyStrong.copyWith(color: colors.textPrimary)),
          ),
          Text('الإصدار $version',
              style: context.text.caption.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

/// Small dialog to change the display name; owns its own submit/error state and
/// calls [AuthController.editName] (PATCH /auth/me), closing itself on success.
class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'الاسم مطلوب.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await context.read<AuthController>().editName(name);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text('تعديل الاسم',
          style: context.text.title.copyWith(color: colors.textPrimary)),
      content: AppTextField(
        label: 'الاسم',
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        error: _error,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.ghost,
          expand: false,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'حفظ',
          loading: _saving,
          expand: false,
          onPressed: _save,
        ),
      ],
    );
  }
}
