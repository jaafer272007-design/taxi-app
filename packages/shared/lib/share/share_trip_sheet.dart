import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../contact/contact_link.dart';
import '../contact/link_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import 'trip_share.dart';

/// Show «شارك رحلتي».
///
/// [onUnavailable] reports a ready-to-show Arabic message when nothing on the
/// device handled the link — a phone without WhatsApp is an ordinary outcome,
/// not an error, and the rider still has the copy button.
Future<void> showShareTripSheet(
  BuildContext context, {
  required TripShareDetails details,
  required LinkLauncher launcher,
  required ValueChanged<String> onUnavailable,
}) {
  final colors = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: RoundedRectangleBorder(borderRadius: context.radii.sheetTop),
    builder: (_) => ShareTripSheet(
      details: details,
      launcher: launcher,
      onUnavailable: onUnavailable,
    ),
  );
}

/// The share sheet body (public so golden tests can render it directly).
///
/// ## Why the message is shown before it is sent
///
/// This is a safety feature, so the rider has to be able to see exactly what
/// leaves their phone. Firing WhatsApp straight from the button with a message
/// they have not read would mean the app decides what to say about where they
/// are and who they are with — which is the opposite of the trust this feature
/// is for. The preview is the feature, not a confirmation step bolted onto it.
///
/// ## Why WhatsApp rather than something in-app
///
/// The recipient does not have the app, and never will — it is a mother, a
/// brother, a friend. Any in-app channel would reach only people who are
/// already users, which excludes almost everyone a rider actually wants to
/// tell. WhatsApp is where Iraqi families already are, it works on wifi with no
/// balance, and the rider picks the recipient in WhatsApp's own contact picker
/// so the app never holds an address book.
class ShareTripSheet extends StatefulWidget {
  const ShareTripSheet({
    super.key,
    required this.details,
    required this.launcher,
    required this.onUnavailable,
  });

  final TripShareDetails details;
  final LinkLauncher launcher;
  final ValueChanged<String> onUnavailable;

  @override
  State<ShareTripSheet> createState() => _ShareTripSheetState();
}

class _ShareTripSheetState extends State<ShareTripSheet> {
  /// Turns «نسخ النص» into «تم النسخ» for a moment. The clipboard gives no
  /// visible feedback of its own, so without this the button looks broken.
  bool _copied = false;

  String get _message => buildTripShareMessage(widget.details);

  Future<void> _openWhatsApp() async {
    final ok = await widget.launcher.open(ContactLink.whatsAppShare(_message));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      widget.onUnavailable('تعذّر فتح واتساب. يمكنك نسخ النص وإرساله بأي طريقة.');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _message));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(space.lg),
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
                  borderRadius: context.radii.pillAll,
                ),
              ),
            ),
            SizedBox(height: space.lg),
            Text('شارك رحلتي',
                style: context.text.title.copyWith(color: colors.textPrimary)),
            SizedBox(height: space.xs),
            Text(
              'اختر بنفسك مَن يستلم هذي الرسالة. التطبيق لا يرسلها لأحد.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
            SizedBox(height: space.lg),

            // The preview. Opaque surfaceMuted, never a translucent tint: this
            // sits on the sheet's own surface and a wash would composite
            // differently in the two themes.
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(space.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: context.radii.cardAll,
              ),
              child: Text(
                _message,
                style: context.text.body.copyWith(color: colors.textPrimary),
              ),
            ),

            SizedBox(height: space.lg),
            AppButton(
              label: 'إرسال عبر واتساب',
              icon: AppIcons.chat,
              onPressed: _openWhatsApp,
            ),
            SizedBox(height: space.sm),
            AppButton(
              // The fallback the brief asks for, and it is not a second-class
              // path: a rider may want Telegram, SMS, or a note to themselves.
              label: _copied ? 'تم نسخ النص' : 'نسخ النص',
              icon: _copied ? AppIcons.check : AppIcons.copy,
              variant: AppButtonVariant.secondary,
              onPressed: _copy,
            ),
          ],
        ),
      ),
    );
  }
}
