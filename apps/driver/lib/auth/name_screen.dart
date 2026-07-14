import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Step 3 — name (new users only).
class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(AuthController auth) {
    final name = _controller.text.trim();
    if (name.length < 2) {
      setState(() => _localError = 'أدخل اسمك الكامل.');
      return;
    }
    setState(() => _localError = null);
    auth.submitName(name);
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
            icon: AppIcons.user,
            title: 'ما اسمك؟',
            subtitle: 'يظهر اسمك للركّاب في رحلاتك.',
          ),
          SizedBox(height: space.xl3),
          AppTextField(
            label: 'الاسم الكامل',
            hint: 'مثال: علي حسن',
            error: _localError ?? auth.error,
            controller: _controller,
            prefixIcon: AppIcons.user,
            textInputAction: TextInputAction.done,
            enabled: !auth.busy,
            onChanged: (_) {
              if (_localError != null) setState(() => _localError = null);
            },
            onSubmitted: (_) => _submit(auth),
          ),
          SizedBox(height: space.xl),
          AppButton(
            label: 'متابعة',
            loading: auth.busy,
            onPressed: auth.busy ? null : () => _submit(auth),
          ),
        ],
      ),
    );
  }
}
