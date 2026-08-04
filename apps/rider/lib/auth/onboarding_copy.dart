import 'package:shared/shared.dart';

/// The rider app's onboarding wording.
///
/// The screens themselves live in `/packages/shared` and are identical for both
/// apps; only these four sentences differ, because a rider is told what signing
/// in gets them (booking a seat) while a driver is told what it gets them
/// (posting trips).
const OnboardingCopy riderOnboardingCopy = OnboardingCopy(
  phoneTitle: 'تكسي مشترك',
  phoneSubtitle: 'سجّل دخولك برقم موبايلك للحجز بين المحافظات.',
  profileSubtitle: 'اسمك وجنسك يظهران للسائق عند الحجز.',
  genderHelper: 'يُستخدم لأهلية الرحلات النسائية/العائلية.',
);
