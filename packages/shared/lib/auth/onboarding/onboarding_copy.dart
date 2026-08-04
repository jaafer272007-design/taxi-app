/// The strings that differ between the rider and driver onboarding flows.
///
/// The three onboarding screens are identical in structure and behaviour across
/// both apps — only four sentences differ, because a rider is told what the flow
/// gets them (booking) and a driver is told what it gets them (posting trips).
/// Passing those four in keeps ONE implementation of the screens instead of two
/// copies drifting apart.
///
/// **Deliberately no `OnboardingCopy.rider` / `.driver` constants here.** Each
/// app declares its own, so the shared screens never learn which app they are
/// running in — the moment shared code can name the two apps, someone will
/// branch on it and the duplication comes back as a conditional.
class OnboardingCopy {
  const OnboardingCopy({
    required this.phoneTitle,
    required this.phoneSubtitle,
    required this.profileSubtitle,
    required this.genderHelper,
  });

  /// Step 1 header title — the product, from this audience's point of view.
  final String phoneTitle;

  /// Step 1 header subtitle — what signing in gets them.
  final String phoneSubtitle;

  /// Step 3 header subtitle — who will see the name and gender they enter.
  final String profileSubtitle;

  /// Step 3 helper under the gender control, shown while no error is pending.
  final String genderHelper;
}
