import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../net/iraqi_phone.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/onboarding_header.dart';
import '../auth_controller.dart';
import 'onboarding_copy.dart';

/// Step 1 — phone entry. Shared by both apps; only the header copy differs.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.copy});

  /// The app-specific header strings. See [OnboardingCopy].
  final OnboardingCopy copy;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(AuthController auth) {
    final normalized = IraqiPhone.normalize(_controller.text);
    if (normalized == null) {
      // Western digits deliberately: this describes what the keyboard
      // produces in the phone field, and inputs stay Western per the locked
      // numerals rule.
      setState(() => _localError = 'أدخل رقم موبايل عراقي صحيح (يبدأ بـ 07).');
      return;
    }
    setState(() => _localError = null);
    auth.requestOtp(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final space = context.space;
    return AppScaffold(
      scrollable: true,
      // Pinned: the primary action stays reachable when the keyboard is up,
      // instead of being pushed under it with the rest of the form.
      bottomBar: AppButton(
        label: 'إرسال الرمز',
        loading: auth.busy,
        onPressed: auth.busy ? null : () => _submit(auth),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.xl2),
          OnboardingHeader(
            step: 1,
            totalSteps: 3,
            icon: AppIcons.car,
            title: widget.copy.phoneTitle,
            subtitle: widget.copy.phoneSubtitle,
          ),
          SizedBox(height: space.xl3),
          AppTextField(
            label: 'رقم الهاتف',
            hint: '07XX XXX XXXX',
            helper: 'سنرسل رمز التحقق عبر واتساب.',
            error: _localError ?? auth.error,
            controller: _controller,
            prefixIcon: AppIcons.phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            enabled: !auth.busy,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            onChanged: (_) {
              if (_localError != null) setState(() => _localError = null);
            },
            onSubmitted: (_) => _submit(auth),
          ),
        ],
      ),
    );
  }
}
