import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Widget tests for the onboarding screens, which live in `shared` because both
/// apps run the SAME implementation. They used to be duplicated per app, so
/// these assertions only ever covered the rider's copy — the driver's screens
/// had no widget tests at all. One implementation means one set of tests that
/// covers both.
///
/// A file-private fake, matching the convention already used by
/// `settings_screen_test.dart` and `settings_golden_test.dart` in this
/// directory.
class _FakeAuthApi implements AuthApi {
  int requestOtpCalls = 0;
  String? lastPhone;
  String? lastName;
  Gender? lastGender;
  AuthUser? meResult;
  Object? meError;

  @override
  Future<void> requestOtp(String phone) async {
    requestOtpCalls++;
    lastPhone = phone;
  }

  @override
  Future<AuthSession> verifyOtp(String phone, String code) async =>
      AuthSession(accessToken: 'jwt', user: _user());

  @override
  Future<AuthUser> me() async {
    if (meError != null) throw meError!;
    return meResult ?? _user();
  }

  @override
  Future<AuthUser> updateName(String name) async {
    lastName = name;
    return _user(name: name);
  }

  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async {
    if (name != null) lastName = name;
    if (gender != null) lastGender = gender;
    return _user(name: name ?? lastName, gender: gender ?? lastGender);
  }
}

AuthUser _user({String? name, Gender? gender}) => AuthUser(
      id: 'u1',
      phone: '+9647701234567',
      name: name,
      gender: gender,
      roles: const ['RIDER'],
      profileComplete: (name?.trim().isNotEmpty ?? false) && gender != null,
    );

/// Stand-ins for the two apps' real copy. Declared here rather than imported so
/// the shared tests stay independent of either app — what they verify is that
/// the copy is *threaded through*, not what any particular app's wording is.
const _riderish = OnboardingCopy(
  phoneTitle: 'تكسي مشترك',
  phoneSubtitle: 'سجّل دخولك برقم موبايلك للحجز بين المحافظات.',
  profileSubtitle: 'اسمك وجنسك يظهران للسائق عند الحجز.',
  genderHelper: 'يُستخدم لأهلية الرحلات النسائية/العائلية.',
);

const _driverish = OnboardingCopy(
  phoneTitle: 'سائق تكسي مشترك',
  phoneSubtitle: 'سجّل دخولك برقم موبايلك لإعلان رحلاتك بين المحافظات.',
  profileSubtitle: 'اسمك وجنسك يظهران للركّاب في رحلاتك.',
  genderHelper: 'يظهر جنسك للركّاب عند اختيار الرحلة.',
);

Widget _host(Widget child, AuthController auth) =>
    ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );

void main() {
  AuthController makeAuth(_FakeAuthApi api, {String? token}) {
    final auth = AuthController(
      api: api,
      tokenStore: InMemoryTokenStore(token),
    );
    // Cleanup only. NOTE: addTearDown runs *after* flutter_test's "a Timer is
    // still pending" invariant, so it cannot rescue a test that leaves the
    // resend-cooldown timer running — that has to be handled inside the test
    // body (see the drain in 'a valid phone is normalised and sent'). Same
    // reasoning as the `auth?.dispose()` closing apps/rider/test/
    // trip_golden_test.dart's `_golden` helper.
    addTearDown(auth.dispose);
    return auth;
  }

  group('PhoneScreen', () {
    testWidgets('invalid phone shows an Arabic error and does not call the API',
        (tester) async {
      final api = _FakeAuthApi();
      final auth = makeAuth(api);
      await tester.pumpWidget(_host(const PhoneScreen(copy: _riderish), auth));

      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('إرسال الرمز'));
      await tester.pump();

      expect(find.textContaining('رقم موبايل عراقي'), findsOneWidget);
      expect(api.requestOtpCalls, 0);
      expect(auth.step, OnboardingStep.phone);
    });

    testWidgets('a valid phone is normalised and sent', (tester) async {
      final api = _FakeAuthApi();
      final auth = makeAuth(api);
      await tester.pumpWidget(_host(const PhoneScreen(copy: _riderish), auth));

      await tester.enterText(find.byType(TextField), '07701234567');
      await tester.tap(find.text('إرسال الرمز'));
      await tester.pumpAndSettle();

      expect(api.requestOtpCalls, 1);
      expect(api.lastPhone, '+9647701234567');
      expect(auth.step, OnboardingStep.otp);

      // Reaching the OTP step starts the 60-second resend cooldown — a periodic
      // timer. Run it out inside the test body: it cancels itself on the last
      // tick, and a timer that outlives the tree trips flutter_test's
      // `!timersPending` assertion before any tearDown gets a turn.
      expect(auth.canResend, isFalse);
      await tester.pump(
        const Duration(seconds: AuthController.resendCooldownSeconds),
      );
      expect(auth.resendSeconds, 0);
      expect(auth.canResend, isTrue);
    });

    testWidgets('the phone field keeps WESTERN digits — the locked input rule',
        (tester) async {
      final api = _FakeAuthApi();
      final auth = makeAuth(api);
      await tester.pumpWidget(_host(const PhoneScreen(copy: _riderish), auth));

      await tester.enterText(find.byType(TextField), '07701234567');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '07701234567');
      expect(field.controller?.text, isNot(matches(RegExp(r'[٠-٩]'))));
    });

    testWidgets('renders whichever copy it is given, and nothing app-specific',
        (tester) async {
      // The one behaviour this refactor actually introduces: the screen shows
      // the caller's strings. If it ever hard-coded one app's wording, the
      // other app would silently ship the wrong text.
      for (final (copy, other) in [
        (_riderish, _driverish),
        (_driverish, _riderish),
      ]) {
        final auth = makeAuth(_FakeAuthApi());
        await tester.pumpWidget(_host(PhoneScreen(copy: copy), auth));

        expect(find.text(copy.phoneTitle), findsOneWidget);
        expect(find.text(copy.phoneSubtitle), findsOneWidget);
        expect(find.text(other.phoneTitle), findsNothing);
        expect(find.text(other.phoneSubtitle), findsNothing);
      }
    });
  });

  group('NameScreen', () {
    testWidgets('renders the name field and both gender segments',
        (tester) async {
      final auth = makeAuth(_FakeAuthApi(), token: 'jwt');
      await tester.pumpWidget(_host(const NameScreen(copy: _riderish), auth));

      expect(find.text('الاسم الكامل'), findsOneWidget);
      expect(find.text('الجنس'), findsOneWidget);
      expect(find.text('رجل'), findsOneWidget);
      expect(find.text('امرأة'), findsOneWidget);
    });

    testWidgets('a name without a gender shows an error and does not submit',
        (tester) async {
      final api = _FakeAuthApi();
      final auth = makeAuth(api, token: 'jwt');
      await tester.pumpWidget(_host(const NameScreen(copy: _riderish), auth));

      await tester.enterText(find.byType(TextField), 'علي حسن');
      await tester.tap(find.text('متابعة'));
      await tester.pump();

      expect(find.text('اختر الجنس للمتابعة.'), findsOneWidget);
      expect(api.lastGender, isNull);
      expect(auth.status, isNot(AuthStatus.authenticated));
    });

    testWidgets('name + gender submits the profile and enters the app',
        (tester) async {
      final api = _FakeAuthApi();
      final auth = makeAuth(api, token: 'jwt');
      await tester.pumpWidget(_host(const NameScreen(copy: _riderish), auth));

      await tester.enterText(find.byType(TextField), 'سارة كريم');
      await tester.tap(find.text('امرأة'));
      await tester.pump();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();

      expect(api.lastName, 'سارة كريم');
      expect(api.lastGender, Gender.female);
      expect(auth.status, AuthStatus.authenticated);
    });

    testWidgets('renders whichever copy it is given, and nothing app-specific',
        (tester) async {
      for (final (copy, other) in [
        (_riderish, _driverish),
        (_driverish, _riderish),
      ]) {
        final auth = makeAuth(_FakeAuthApi(), token: 'jwt');
        await tester.pumpWidget(_host(NameScreen(copy: copy), auth));

        expect(find.text(copy.profileSubtitle), findsOneWidget);
        expect(find.text(copy.genderHelper), findsOneWidget);
        expect(find.text(other.profileSubtitle), findsNothing);
        expect(find.text(other.genderHelper), findsNothing);
      }
    });

    testWidgets('the gender error replaces the helper, then restores it',
        (tester) async {
      final auth = makeAuth(_FakeAuthApi(), token: 'jwt');
      await tester.pumpWidget(_host(const NameScreen(copy: _driverish), auth));

      expect(find.text(_driverish.genderHelper), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'علي حسن');
      await tester.tap(find.text('متابعة'));
      await tester.pump();
      expect(find.text('اختر الجنس للمتابعة.'), findsOneWidget);
      expect(find.text(_driverish.genderHelper), findsNothing);

      await tester.tap(find.text('رجل'));
      await tester.pump();
      expect(find.text(_driverish.genderHelper), findsOneWidget);
    });
  });

  group('OnboardingFlow', () {
    testWidgets('shows the step the controller is on, threading the copy',
        (tester) async {
      final auth = makeAuth(_FakeAuthApi());
      await tester
          .pumpWidget(_host(const OnboardingFlow(copy: _driverish), auth));

      expect(find.byType(PhoneScreen), findsOneWidget);
      expect(find.text(_driverish.phoneTitle), findsOneWidget);
    });

    testWidgets(
        'a valid token with no gender lands on the name step, not the app',
        (tester) async {
      // The profileComplete routing rule: an existing user who predates the
      // gender field has a working JWT but an incomplete profile, and must be
      // sent to step 3 rather than into the app.
      final api = _FakeAuthApi()..meResult = _user(name: 'علي حسن');
      final auth = makeAuth(api, token: 'jwt');
      await auth.bootstrap();
      await tester
          .pumpWidget(_host(const OnboardingFlow(copy: _riderish), auth));
      await tester.pumpAndSettle();

      expect(auth.status, AuthStatus.onboarding);
      expect(auth.step, OnboardingStep.name);
      expect(find.byType(NameScreen), findsOneWidget);
      // …and their existing name is prefilled so they only add the gender.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'علي حسن',
      );
    });
  });
}
