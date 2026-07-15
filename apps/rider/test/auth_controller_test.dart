import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'package:shared/shared.dart';

void main() {
  late FakeAuthApi api;
  late InMemoryTokenStore store;

  AuthController make() {
    final controller = AuthController(api: api, tokenStore: store);
    addTearDown(controller.dispose); // cancels the resend timer
    return controller;
  }

  setUp(() {
    api = FakeAuthApi();
    store = InMemoryTokenStore();
  });

  group('bootstrap', () {
    test('no token → onboarding at phone step', () async {
      final c = make();
      await c.bootstrap();
      expect(c.status, AuthStatus.onboarding);
      expect(c.step, OnboardingStep.phone);
    });

    test('valid token + complete profile → authenticated (skips onboarding)',
        () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser(name: 'علي', gender: Gender.male);
      final c = make();
      await c.bootstrap();
      expect(c.status, AuthStatus.authenticated);
      expect(c.user?.name, 'علي');
    });

    test('valid token + nameless user → onboarding at name step', () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser();
      final c = make();
      await c.bootstrap();
      expect(c.status, AuthStatus.onboarding);
      expect(c.step, OnboardingStep.name);
    });

    test('valid token + name but no gender → onboarding (pre-gender user)',
        () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser(name: 'علي'); // has a name, gender still null
      final c = make();
      await c.bootstrap();
      expect(c.user?.profileComplete, isFalse);
      expect(c.status, AuthStatus.onboarding);
      expect(c.step, OnboardingStep.name);
    });

    test('invalid/expired token → cleared, onboarding at phone', () async {
      store = InMemoryTokenStore('bad');
      api.meError = const ApiException('unauthorized', statusCode: 401);
      final c = make();
      await c.bootstrap();
      expect(c.status, AuthStatus.onboarding);
      expect(c.step, OnboardingStep.phone);
      expect(await store.read(), isNull);
    });
  });

  group('requestOtp', () {
    test('success → otp step, cooldown started, resend blocked', () async {
      final c = make();
      await c.requestOtp('+9647701234567');
      expect(api.requestOtpCalls, 1);
      expect(api.lastPhone, '+9647701234567');
      expect(c.step, OnboardingStep.otp);
      expect(c.phone, '+9647701234567');
      expect(c.resendSeconds, AuthController.resendCooldownSeconds);
      expect(c.canResend, isFalse);
      expect(c.error, isNull);
    });

    test('failure → error set, stays on phone step', () async {
      api.requestOtpError =
          const ApiException('محاولات كثيرة', statusCode: 429);
      final c = make();
      await c.requestOtp('+9647701234567');
      expect(c.step, OnboardingStep.phone);
      expect(c.error, 'محاولات كثيرة');
    });
  });

  group('verifyOtp', () {
    test('incomplete profile → JWT stored, advances to name step', () async {
      api.verifyResult = AuthSession(accessToken: 'jwt', user: fakeUser());
      final c = make();
      await c.bootstrap(); // onboarding/phone (empty store)
      await c.requestOtp('+9647701234567'); // reach the otp step
      await c.verifyOtp('123456');
      expect(await store.read(), 'jwt');
      expect(c.step, OnboardingStep.name);
      expect(c.status, AuthStatus.onboarding);
    });

    test('complete profile → JWT stored, authenticated', () async {
      api.verifyResult = AuthSession(
        accessToken: 'jwt',
        user: fakeUser(name: 'سارة', gender: Gender.female),
      );
      final c = make();
      await c.verifyOtp('123456');
      expect(await store.read(), 'jwt');
      expect(c.status, AuthStatus.authenticated);
    });

    test('wrong code → Arabic error, no token stored', () async {
      api.verifyError =
          const ApiException('رمز التحقق غير صحيح.', statusCode: 401);
      final c = make();
      await c.bootstrap();
      await c.requestOtp('+9647701234567'); // reach the otp step
      await c.verifyOtp('000000');
      expect(c.error, 'رمز التحقق غير صحيح.');
      expect(await store.read(), isNull);
      expect(c.step, OnboardingStep.otp);
    });
  });

  group('submitProfile', () {
    test('saves name + gender → authenticated', () async {
      final c = make();
      await c.submitProfile(name: 'علي حسن', gender: Gender.male);
      expect(api.lastName, 'علي حسن');
      expect(api.lastGender, Gender.male);
      expect(c.status, AuthStatus.authenticated);
      expect(c.user?.name, 'علي حسن');
      expect(c.user?.gender, Gender.male);
    });

    test('stays on the profile step when the backend reports incomplete',
        () async {
      final c = make();
      // Server echoes back an incomplete profile (should not slip into the app).
      api.updateProfileResult = fakeUser(name: 'علي حسن');
      await c.submitProfile(name: 'علي حسن', gender: Gender.male);
      expect(c.user?.profileComplete, isFalse);
      expect(c.status, isNot(AuthStatus.authenticated));
    });
  });

  test('changePhone → back to phone step, error cleared', () async {
    api.requestOtpError = const ApiException('x');
    final c = make();
    await c.requestOtp('+9647701234567');
    expect(c.error, 'x');
    c.changePhone();
    expect(c.step, OnboardingStep.phone);
    expect(c.error, isNull);
  });

  group('logout', () {
    test('clears the JWT and returns to onboarding at phone step', () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser(name: 'علي', gender: Gender.male);
      final c = make();
      await c.bootstrap();
      expect(c.status, AuthStatus.authenticated);

      await c.logout();

      expect(await store.read(), isNull);
      expect(c.status, AuthStatus.onboarding);
      expect(c.step, OnboardingStep.phone);
      expect(c.user, isNull);
    });
  });

  group('editName (settings)', () {
    test('updates the user via PATCH /auth/me and stays authenticated',
        () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser(name: 'علي', gender: Gender.male);
      final c = make();
      await c.bootstrap();

      final err = await c.editName('علي حسن');

      expect(err, isNull);
      expect(api.lastName, 'علي حسن');
      expect(c.user?.name, 'علي حسن');
      expect(c.status, AuthStatus.authenticated);
    });

    test('returns the Arabic error and keeps the old name on failure', () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser(name: 'علي', gender: Gender.male);
      final c = make();
      await c.bootstrap();
      api.updateNameError = const ApiException('تعذّر الحفظ.', statusCode: 400);

      final err = await c.editName('اسم جديد');

      expect(err, 'تعذّر الحفظ.');
      expect(c.user?.name, 'علي'); // unchanged
      expect(c.status, AuthStatus.authenticated);
    });
  });
}
