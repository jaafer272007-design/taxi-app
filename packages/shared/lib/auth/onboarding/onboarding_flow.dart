import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_controller.dart';
import 'name_screen.dart';
import 'onboarding_copy.dart';
import 'otp_screen.dart';
import 'phone_screen.dart';

/// Shows the current onboarding screen based on the controller's step, with a
/// gentle cross-fade between steps.
///
/// Where each app goes AFTER onboarding is not this widget's business: both
/// routers switch on [AuthController.status], so reaching `authenticated` moves
/// the app on by itself. That is why there is no destination parameter here.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key, required this.copy});

  /// The app-specific strings, handed down to the steps that need them.
  final OnboardingCopy copy;

  @override
  Widget build(BuildContext context) {
    final step = context.select<AuthController, OnboardingStep>((c) => c.step);
    final Widget screen = switch (step) {
      OnboardingStep.phone => PhoneScreen(copy: copy),
      OnboardingStep.otp => const OtpScreen(),
      OnboardingStep.name => NameScreen(copy: copy),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(step), child: screen),
    );
  }
}
