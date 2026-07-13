import 'package:flutter_test/flutter_test.dart';
import 'package:rider/auth/auth_controller.dart';
import 'package:rider/auth/auth_user.dart';
import 'package:rider/core/api_exception.dart';
import 'package:rider/core/token_store.dart';

import 'support/fakes.dart';

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

    test('valid token + named user → authenticated (skips onboarding)',
        () async {
      store = InMemoryTokenStore('jwt');
      api.meResult = fakeUser(name: 'علي');
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
    test('nameless user → JWT stored, advances to name step', () async {
      api.verifyResult = AuthSession(accessToken: 'jwt', user: fakeUser());
      final c = make();
      await c.verifyOtp('123456');
      expect(await store.read(), 'jwt');
      expect(c.step, OnboardingStep.name);
      expect(c.status, AuthStatus.onboarding);
    });

    test('named user → JWT stored, authenticated', () async {
      api.verifyResult =
          AuthSession(accessToken: 'jwt', user: fakeUser(name: 'سارة'));
      final c = make();
      await c.verifyOtp('123456');
      expect(await store.read(), 'jwt');
      expect(c.status, AuthStatus.authenticated);
    });

    test('wrong code → Arabic error, no token stored', () async {
      api.verifyError =
          const ApiException('رمز التحقق غير صحيح.', statusCode: 401);
      final c = make();
      await c.verifyOtp('000000');
      expect(c.error, 'رمز التحقق غير صحيح.');
      expect(await store.read(), isNull);
      expect(c.step, OnboardingStep.otp);
    });
  });

  test('submitName → saved and authenticated', () async {
    final c = make();
    await c.submitName('علي حسن');
    expect(api.lastName, 'علي حسن');
    expect(c.status, AuthStatus.authenticated);
    expect(c.user?.name, 'علي حسن');
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
}
