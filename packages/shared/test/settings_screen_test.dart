import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// A minimal [AuthApi] fake: `me()` returns a fixed named user; `updateName`
/// echoes the new name back.
class _FakeAuthApi implements AuthApi {
  _FakeAuthApi();

  /// What the server currently holds. Stateful because the emergency-contact
  /// flow is a round trip: save, then the card has to redraw from the result.
  EmergencyContact? saved;
  int saveCalls = 0;

  /// Set to make the next save fail, as the server's 400 would.
  String? saveError;

  static const _user = AuthUser(
    id: 'u1',
    phone: '+9647701234567',
    name: 'علي حسن',
    gender: Gender.male,
    roles: ['RIDER'],
    profileComplete: true,
  );

  @override
  Future<void> requestOtp(String phone) async {}

  @override
  Future<AuthSession> verifyOtp(String phone, String code) async =>
      throw UnimplementedError();

  @override
  Future<AuthUser> me() async => _withContact(_user);

  AuthUser _withContact(AuthUser u) => AuthUser(
        id: u.id,
        phone: u.phone,
        name: u.name,
        gender: u.gender,
        roles: u.roles,
        profileComplete: u.profileComplete,
        emergencyContact: saved,
      );

  @override
  Future<AuthUser> updateEmergencyContact(EmergencyContact? contact) async {
    saveCalls++;
    if (saveError != null) throw ApiException(saveError!);
    saved = contact;
    return _withContact(_user);
  }

  @override
  Future<AuthUser> updateName(String name) async => AuthUser(
        id: 'u1',
        phone: '+9647701234567',
        name: name,
        gender: Gender.male,
        roles: const ['RIDER'],
        profileComplete: true,
      );

  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async =>
      AuthUser(
        id: 'u1',
        phone: '+9647701234567',
        name: name ?? _user.name,
        gender: gender ?? _user.gender,
        roles: const ['RIDER'],
        profileComplete: true,
      );
}

Widget _host(ThemeController theme, AuthController auth) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsScreen(
      appVersion: '0.1.0',
      onLogout: () async {},
      showEmergencyContact: true,
    ),
        ),
      ),
    );

AppSegmentedControl<ThemeMode> _control(WidgetTester t) =>
    t.widget<AppSegmentedControl<ThemeMode>>(
      find.byWidgetPredicate((w) => w is AppSegmentedControl<ThemeMode>),
    );

void main() {
  _emergencyTests();

  testWidgets('theme selector reflects the ThemeController and sets it',
      (t) async {
    final theme =
        ThemeController(store: InMemoryThemeModeStore()); // default: system
    final auth =
        AuthController(api: _FakeAuthApi(), tokenStore: InMemoryTokenStore());
    addTearDown(auth.dispose);

    await t.pumpWidget(_host(theme, auth));
    await t.pump();

    // All three options are present, and the control reflects the current mode.
    expect(find.text('فاتح'), findsOneWidget);
    expect(find.text('داكن'), findsOneWidget);
    expect(find.text('حسب النظام'), findsOneWidget);
    expect(_control(t).value, ThemeMode.system);

    // Selecting "داكن" sets the controller and the control now reflects it.
    _control(t).onChanged(ThemeMode.dark);
    await t.pump();
    expect(theme.mode, ThemeMode.dark);
    expect(_control(t).value, ThemeMode.dark);

    _control(t).onChanged(ThemeMode.light);
    await t.pump();
    expect(theme.mode, ThemeMode.light);
    expect(_control(t).value, ThemeMode.light);
  });

  testWidgets('shows the signed-in name and phone', (t) async {
    final theme = ThemeController(store: InMemoryThemeModeStore());
    final auth = AuthController(
      api: _FakeAuthApi(),
      tokenStore: InMemoryTokenStore('jwt'),
    );
    addTearDown(auth.dispose);
    await auth.bootstrap(); // me() → named user, authenticated

    await t.pumpWidget(_host(theme, auth));
    await t.pump();

    expect(find.text('علي حسن'), findsOneWidget);
    expect(find.text('+9647701234567'), findsOneWidget);
    expect(find.text('الإصدار 0.1.0'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
  });
}

// ── The optional emergency contact ──────────────────────────────────────────
//
// The acceptance rule is a NEGATIVE one — "a rider who saves nothing sees no
// emergency UI anywhere" — and negatives are what silently stop holding when a
// later change adds a nudge. So the absence is asserted, not assumed.

Future<AuthController> _signedIn(_FakeAuthApi api) async {
  final auth = AuthController(api: api, tokenStore: InMemoryTokenStore('jwt'));
  addTearDown(auth.dispose);
  await auth.bootstrap();
  return auth;
}

void _emergencyTests() {
  testWidgets('with nothing saved: an unobtrusive row, and no nagging',
      (t) async {
    final api = _FakeAuthApi();
    final auth = await _signedIn(api);
    await t.pumpWidget(
        _host(ThemeController(store: InMemoryThemeModeStore()), auth));
    await t.pump();

    // The settings row itself is the disclosure, and it is allowed to exist.
    expect(find.text('جهة اتصال للطوارئ'), findsOneWidget);
    expect(find.text('إضافة جهة اتصال'), findsOneWidget);
    // But nothing that reads as a prompt, a warning, or an incomplete task.
    expect(find.byIcon(AppIcons.warning), findsNothing);
    expect(find.text('تعديل'), findsNothing);
    expect(api.saveCalls, 0);
  });

  testWidgets('saving one round-trips and redraws the card', (t) async {
    final api = _FakeAuthApi();
    final auth = await _signedIn(api);
    await t.pumpWidget(
        _host(ThemeController(store: InMemoryThemeModeStore()), auth));
    await t.pump();

    await t.tap(find.text('إضافة جهة اتصال'));
    await t.pumpAndSettle();

    // The promise the dialog makes is part of the feature, so it is pinned.
    expect(find.textContaining('لن يظهر هذا الرقم لأي شخص آخر'), findsOneWidget);

    await t.enterText(find.widgetWithText(AppTextField, 'الاسم').last, 'أم علي');
    await t.enterText(
        find.widgetWithText(AppTextField, 'رقم الهاتف'), '07701112233');
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();

    expect(api.saveCalls, 1);
    expect(api.saved?.name, 'أم علي');
    expect(api.saved?.phone, '07701112233');
    // The card now shows it back — a saved-but-wrong number is only ever
    // discovered in the moment it is needed, so it has to be checkable here.
    expect(find.text('أم علي'), findsOneWidget);
    expect(find.text('+964 770 111 2233'), findsOneWidget);
    expect(find.text('إضافة جهة اتصال'), findsNothing);
  });

  testWidgets('a server rejection stays in the dialog and says why', (t) async {
    final api = _FakeAuthApi()..saveError = 'رقم جهة الاتصال غير صالح.';
    final auth = await _signedIn(api);
    await t.pumpWidget(
        _host(ThemeController(store: InMemoryThemeModeStore()), auth));
    await t.pump();

    await t.tap(find.text('إضافة جهة اتصال'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(AppTextField, 'الاسم').last, 'أم علي');
    await t.enterText(find.widgetWithText(AppTextField, 'رقم الهاتف'), '123');
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();

    expect(find.text('رقم جهة الاتصال غير صالح.'), findsOneWidget);
    expect(api.saved, isNull);
  });

  testWidgets('removing it clears the contact and the card goes back to empty',
      (t) async {
    final api = _FakeAuthApi()
      ..saved = const EmergencyContact(name: 'أم علي', phone: '+9647701112233');
    final auth = await _signedIn(api);
    await t.pumpWidget(
        _host(ThemeController(store: InMemoryThemeModeStore()), auth));
    await t.pump();

    expect(find.text('أم علي'), findsOneWidget);
    await t.tap(find.text('تعديل'));
    await t.pumpAndSettle();
    await t.tap(find.text('إزالة'));
    await t.pumpAndSettle();

    // NULL, not an empty contact — that is what tells the server to clear it.
    expect(api.saved, isNull);
    expect(find.text('إضافة جهة اتصال'), findsOneWidget);
    expect(find.text('أم علي'), findsNothing);
  });
}
