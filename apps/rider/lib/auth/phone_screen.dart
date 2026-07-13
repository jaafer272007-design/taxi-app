import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../core/iraqi_phone.dart';
import '../widgets/onboarding_header.dart';
import 'auth_controller.dart';

/// Step 1 — phone entry.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.xl2),
          const OnboardingHeader(
            icon: AppIcons.car,
            title: 'تكسي مشترك',
            subtitle: 'سجّل دخولك برقم موبايلك للحجز بين المحافظات.',
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
          SizedBox(height: space.xl),
          AppButton(
            label: 'إرسال الرمز',
            loading: auth.busy,
            onPressed: auth.busy ? null : () => _submit(auth),
          ),
        ],
      ),
    );
  }
}
