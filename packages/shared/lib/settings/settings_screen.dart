import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_user.dart';
import '../contact/contact_link.dart';
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
    this.showEmergencyContact = false,
  });

  /// Shown in the About section (e.g. "0.1.0").
  final String appVersion;

  /// App-provided logout action; clears the session so the router shows login.
  final Future<void> Function() onLogout;

  /// Show the optional emergency-contact section. **Rider app only.**
  ///
  /// Off by default because the action it enables — «اتصال طارئ» during an
  /// active trip — exists only on the rider's booking card. Offering a driver
  /// a setting that changes nothing they will ever see is worse than not
  /// offering it: they would save a number believing it does something.
  /// (A driver-side equivalent is a real gap, but building half of it here
  /// would hide that rather than fix it.)
  final bool showEmergencyContact;

  void _editName(BuildContext context) {
    final name = context.read<AuthController>().user?.name ?? '';
    showDialog<void>(
      context: context,
      builder: (_) => _EditNameDialog(initialName: name),
    );
  }

  void _editEmergencyContact(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _EmergencyContactDialog(
        initial: context.read<AuthController>().user?.emergencyContact,
      ),
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
          if (showEmergencyContact) ...[
            SizedBox(height: space.xl),
            const _SectionHeader(label: 'الأمان'),
            SizedBox(height: space.sm),
            _EmergencyContactCard(
              contact: user?.emergencyContact,
              onEdit: () => _editEmergencyContact(context),
            ),
          ],
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
          // Western: a version string is an identifier, not a quantity — it has
          // to match what appears in the store listing and in bug reports.
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
      shape: RoundedRectangleBorder(borderRadius: context.radii.cardAll),
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

/// The optional emergency contact.
///
/// ## Optional means optional
///
/// Empty is the default and stays the default: the card states what the feature
/// is in one line and offers a way in. There is no prompt anywhere else in the
/// app, no badge, no red dot, and nothing about it appears on any trip screen
/// until a contact is actually saved. A rider who never touches this feature
/// should never notice it exists beyond this one row.
///
/// ## Why the number is shown back
///
/// A saved-but-wrong number is worse than none: it is only ever dialled in the
/// moment it matters, so a typo stays invisible until exactly then. The card
/// shows the number in the same Western-digits-LTR form the rest of the app
/// uses for phone numbers (CLAUDE.md — a number to dial is an identifier, not a
/// quantity), so the rider can check it against their own contact list.
class _EmergencyContactCard extends StatelessWidget {
  const _EmergencyContactCard({required this.contact, required this.onEdit});

  final EmergencyContact? contact;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final saved = contact;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.shield, size: space.lg, color: colors.textSecondary),
              SizedBox(width: space.sm),
              Expanded(
                child: Text('جهة اتصال للطوارئ',
                    style: context.text.bodyStrong
                        .copyWith(color: colors.textPrimary)),
              ),
            ],
          ),
          SizedBox(height: space.xs),
          Text(
            saved == null
                ? 'اختياري. إذا أضفتها، يظهر زر اتصال سريع أثناء الرحلة فقط.'
                : 'يظهر زر «اتصال طارئ» أثناء الرحلة فقط.',
            style: context.text.caption.copyWith(color: colors.textMuted),
          ),
          if (saved != null) ...[
            SizedBox(height: space.md),
            Text(saved.name,
                style: context.text.body.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            SizedBox(height: space.xs),
            Text(
              ContactLink.display(saved.phone),
              // A number to dial, matched against the phone's own contacts —
              // Western and forced LTR, the documented exception.
              textDirection: TextDirection.ltr,
              style: context.text.body.tabular
                  .copyWith(color: colors.textSecondary),
            ),
          ],
          SizedBox(height: space.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: saved == null ? 'إضافة جهة اتصال' : 'تعديل',
              icon: saved == null ? AppIcons.plus : AppIcons.user,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Add / edit / remove the emergency contact.
///
/// The remove action lives here rather than on the card because it only exists
/// once there is something to remove, and putting it in the dialog keeps the
/// settings row to a single affordance.
class _EmergencyContactDialog extends StatefulWidget {
  const _EmergencyContactDialog({required this.initial});

  final EmergencyContact? initial;

  @override
  State<_EmergencyContactDialog> createState() => _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<_EmergencyContactDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.initial?.phone ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit(EmergencyContact? contact) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await context.read<AuthController>().saveEmergencyContact(contact);
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

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم جهة الاتصال مطلوب.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'رقم جهة الاتصال مطلوب.');
      return;
    }
    // The exact +964 rule is the server's — checking only for "empty" here
    // keeps one definition of a valid Iraqi number instead of two that drift.
    await _submit(EmergencyContact(name: name, phone: phone));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: context.radii.cardAll),
      title: Text('جهة اتصال للطوارئ',
          style: context.text.title.copyWith(color: colors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'لن يظهر هذا الرقم لأي شخص آخر — لا للسائق ولا لغيره.',
            style: context.text.caption.copyWith(color: colors.textMuted),
          ),
          SizedBox(height: space.md),
          AppTextField(
            label: 'الاسم',
            hint: 'مثال: أم علي',
            controller: _name,
            autofocus: widget.initial == null,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
          ),
          SizedBox(height: space.md),
          AppTextField(
            label: 'رقم الهاتف',
            hint: '07XX XXX XXXX',
            controller: _phone,
            prefixIcon: AppIcons.phone,
            keyboardType: TextInputType.phone,
            enabled: !_saving,
            error: _error,
            textInputAction: TextInputAction.done,
            // Input stays WESTERN (CLAUDE.md): the keyboard emits Western
            // digits and converting mid-typing is real friction.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null)
          AppButton(
            label: 'إزالة',
            variant: AppButtonVariant.dangerTonal,
            expand: false,
            onPressed: _saving ? null : () => _submit(null),
          ),
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
