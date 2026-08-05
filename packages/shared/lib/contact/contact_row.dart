import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import 'contact_link.dart';
import 'link_launcher.dart';

/// Someone's phone number with the two ways an Iraqi actually reaches them.
///
/// ## Why both, and why WhatsApp is not the afterthought
///
/// In a real كراج ride the driver calls to pin down the exact spot — a
/// neighbourhood name does not get a car to a door. But WhatsApp is how Iraqis
/// communicate: it works over wifi, it survives a dead balance, and it carries
/// a dropped pin or a photo of the gate, which a voice call cannot. So the two
/// actions are peers, side by side, neither demoted to an overflow menu.
///
/// ## Only ever rendered after a booking exists
///
/// This widget has no idea whether the viewer is entitled to the number — it
/// draws whatever it is handed. The entitlement rule lives on the server
/// (`GET /trips/:id/contacts`, TripContactService), and every screen using this
/// gets its [phone] from there. Nothing pre-booking has a number to pass.
class ContactRow extends StatelessWidget {
  const ContactRow({
    super.key,
    required this.phone,
    required this.launcher,
    this.name,
    this.roleLabel,
    this.onUnavailable,
    this.compact = false,
  });

  /// E.164, as the server stores it (`+9647701234567`).
  final String phone;

  final LinkLauncher launcher;

  /// Who this is. Falls back to [roleLabel] when the profile has no name yet.
  final String? name;

  /// What they are to the viewer — «السائق» / «الراكب».
  final String? roleLabel;

  /// Called when neither the dialer nor WhatsApp could be opened, so the screen
  /// can say so rather than leaving a tap that visibly does nothing.
  final ValueChanged<String>? onUnavailable;

  /// Drop the avatar and tighten the spacing, for use inside a card that
  /// already shows who this person is.
  final bool compact;

  Future<void> _call() async {
    if (!await launcher.open(ContactLink.tel(phone))) {
      onUnavailable?.call('تعذّر فتح تطبيق الاتصال على هذا الجهاز.');
    }
  }

  Future<void> _whatsApp() async {
    if (!await launcher.open(ContactLink.whatsApp(phone))) {
      onUnavailable?.call('تعذّر فتح واتساب. تأكد من تثبيته على جهازك.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final title = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (roleLabel ?? 'جهة الاتصال');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(AppIcons.phone, size: space.lg, color: colors.textMuted),
            SizedBox(width: space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact)
                    Text(
                      title,
                      style: context.text.bodyStrong
                          .copyWith(color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (!compact) SizedBox(height: space.xs),
                  // Western digits, forced LTR. A phone number is an identifier
                  // to dial and match against the contact list, not a quantity
                  // — and `+٩٦٤ ٧٧١…` in an RTL line is the bidi hazard from
                  // the numerals rule with a `+` sign added on top.
                  Text(
                    ContactLink.display(phone),
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
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'اتصال',
                icon: AppIcons.phone,
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: _call,
              ),
            ),
            SizedBox(width: space.sm),
            Expanded(
              child: AppButton(
                // The word carries the identity — the icon is a generic chat
                // bubble, because we ship no WhatsApp brand asset. See
                // AppIcons.chat.
                label: 'واتساب',
                icon: AppIcons.chat,
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: _whatsApp,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
