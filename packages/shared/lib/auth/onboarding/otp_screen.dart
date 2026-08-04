import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../format/numerals.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/onboarding_header.dart';
import '../../widgets/otp_input.dart';
import '../auth_controller.dart';

/// Step 2 — OTP verification.
///
/// Takes no [OnboardingCopy]: every string here is the same for a rider and a
/// driver, and an unused parameter for symmetry would be a lie about what
/// varies.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final colors = context.colors;
    final space = context.space;
    final complete = _code.length == 6;

    return AppScaffold(
      scrollable: true,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'تأكيد',
            loading: auth.busy,
            onPressed: (complete && !auth.busy)
                ? () => context.read<AuthController>().verifyOtp(_code)
                : null,
          ),
          SizedBox(height: space.sm),
          AppButton(
            label: 'تغيير الرقم',
            variant: AppButtonVariant.ghost,
            onPressed: auth.busy
                ? null
                : () => context.read<AuthController>().changePhone(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.xl2),
          OnboardingHeader(
            step: 2,
            totalSteps: 3,
            title: 'أدخل رمز التحقق',
            subtitle: 'أرسلنا رمزاً من ٦ أرقام إلى ${auth.phone}',
          ),
          SizedBox(height: space.xl2),
          OtpInput(
            enabled: !auth.busy,
            hasError: auth.error != null,
            onChanged: (code) {
              setState(() => _code = code);
              if (auth.error != null) context.read<AuthController>().clearError();
            },
            onCompleted: (code) =>
                context.read<AuthController>().verifyOtp(code),
          ),
          if (auth.error != null) ...[
            SizedBox(height: space.md),
            Row(
              children: [
                Icon(AppIcons.danger, size: space.lg, color: colors.danger),
                SizedBox(width: space.xs),
                Expanded(
                  child: Text(
                    auth.error!,
                    style: context.text.label.copyWith(color: colors.danger),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: space.xl),
          const Center(child: _ResendControl()),
        ],
      ),
    );
  }
}

/// Resend button that turns into a countdown while the cooldown is active.
class _ResendControl extends StatelessWidget {
  const _ResendControl();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.canResend) {
      return AppButton(
        label: 'إعادة إرسال الرمز',
        variant: AppButtonVariant.ghost,
        expand: false,
        onPressed: () => context.read<AuthController>().resendOtp(),
      );
    }
    return Text(
      'إعادة الإرسال بعد ${formatCount(auth.resendSeconds)} ثانية',
      style: context.text.caption.copyWith(color: context.colors.textMuted),
    );
  }
}
