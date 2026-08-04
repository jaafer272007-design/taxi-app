import 'package:shared/shared.dart';

/// The driver app's onboarding wording.
///
/// The screens themselves live in `/packages/shared` and are identical for both
/// apps; only these four sentences differ, because a driver is told what signing
/// in gets them (posting trips) while a rider is told what it gets them
/// (booking a seat).
const OnboardingCopy driverOnboardingCopy = OnboardingCopy(
  phoneTitle: 'سائق تكسي مشترك',
  phoneSubtitle: 'سجّل دخولك برقم موبايلك لإعلان رحلاتك بين المحافظات.',
  profileSubtitle: 'اسمك وجنسك يظهران للركّاب في رحلاتك.',
  genderHelper: 'يظهر جنسك للركّاب عند اختيار الرحلة.',
);
