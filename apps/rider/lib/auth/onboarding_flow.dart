import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'name_screen.dart';
import 'otp_screen.dart';
import 'phone_screen.dart';
import 'package:shared/shared.dart';

/// Shows the current onboarding screen based on the controller's step, with a
/// gentle cross-fade between steps.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.select<AuthController, OnboardingStep>((c) => c.step);
    final Widget screen = switch (step) {
      OnboardingStep.phone => const PhoneScreen(),
      OnboardingStep.otp => const OtpScreen(),
      OnboardingStep.name => const NameScreen(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(step), child: screen),
    );
  }
}
