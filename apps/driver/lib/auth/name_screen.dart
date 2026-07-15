import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Step 3 — profile completion (name + gender). Shown to brand-new users and to
/// any existing user whose profile is still incomplete (e.g. a pre-gender user
/// who has a name but no gender). Both fields are required before the app opens.
class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _controller = TextEditingController();
  Gender? _gender;
  String? _nameError;
  bool _genderMissing = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill for a pre-gender user who already has a name (they only need to
    // add their gender), so they don't have to retype it.
    final existing = context.read<AuthController>().user;
    if (existing?.name != null) _controller.text = existing!.name!;
    _gender = existing?.gender;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(AuthController auth) {
    final name = _controller.text.trim();
    final nameError = name.length < 2 ? 'أدخل اسمك الكامل.' : null;
    final genderMissing = _gender == null;
    if (nameError != null || genderMissing) {
      setState(() {
        _nameError = nameError;
        _genderMissing = genderMissing;
      });
      return;
    }
    setState(() {
      _nameError = null;
      _genderMissing = false;
    });
    auth.submitProfile(name: name, gender: _gender!);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final space = context.space;
    final colors = context.colors;
    return AppScaffold(
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.xl2),
          const OnboardingHeader(
            icon: AppIcons.user,
            title: 'عرّفنا بنفسك',
            subtitle: 'اسمك وجنسك يظهران للركّاب في رحلاتك.',
          ),
          SizedBox(height: space.xl3),
          AppTextField(
            label: 'الاسم الكامل',
            hint: 'مثال: علي حسن',
            error: _nameError ?? auth.error,
            controller: _controller,
            prefixIcon: AppIcons.user,
            textInputAction: TextInputAction.done,
            enabled: !auth.busy,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: (_) => _submit(auth),
          ),
          SizedBox(height: space.xl),
          Text(
            'الجنس',
            style: context.text.label.copyWith(color: colors.textSecondary),
          ),
          SizedBox(height: space.sm),
          AppSegmentedControl<Gender?>(
            value: _gender,
            segments: const <AppSegment<Gender?>>[
              AppSegment(value: Gender.male, label: 'رجل'),
              AppSegment(value: Gender.female, label: 'امرأة'),
            ],
            onChanged: (g) => setState(() {
              _gender = g;
              _genderMissing = false;
            }),
          ),
          SizedBox(height: space.xs),
          Text(
            _genderMissing
                ? 'اختر الجنس للمتابعة.'
                : 'يظهر جنسك للركّاب عند اختيار الرحلة.',
            style: context.text.caption.copyWith(
              color: _genderMissing ? colors.danger : colors.textMuted,
            ),
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
