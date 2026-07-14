import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Step 2 — OTP verification.
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.xl2),
          OnboardingHeader(
            title: 'أدخل رمز التحقق',
            subtitle: 'أرسلنا رمزاً من 6 أرقام إلى ${auth.phone}',
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
          SizedBox(height: space.xl),
          AppButton(
            label: 'تأكيد',
            loading: auth.busy,
            onPressed: (complete && !auth.busy)
                ? () => context.read<AuthController>().verifyOtp(_code)
                : null,
          ),
          SizedBox(height: space.sm),
          Center(
            child: AppButton(
              label: 'تغيير الرقم',
              variant: AppButtonVariant.ghost,
              expand: false,
              onPressed: auth.busy
                  ? null
                  : () => context.read<AuthController>().changePhone(),
            ),
          ),
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
      'إعادة الإرسال بعد ${auth.resendSeconds} ثانية',
      style: context.text.caption.copyWith(color: context.colors.textMuted),
    );
  }
}
