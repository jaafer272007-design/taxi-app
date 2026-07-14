import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// A minimal [AuthApi] fake: `me()` returns a fixed named user; `updateName`
/// echoes the new name back.
class _FakeAuthApi implements AuthApi {
  const _FakeAuthApi();

  static const _user = AuthUser(
    id: 'u1',
    phone: '+9647701234567',
    name: 'علي حسن',
    roles: ['RIDER'],
  );

  @override
  Future<void> requestOtp(String phone) async {}

  @override
  Future<AuthSession> verifyOtp(String phone, String code) async =>
      throw UnimplementedError();

  @override
  Future<AuthUser> me() async => _user;

  @override
  Future<AuthUser> updateName(String name) async => AuthUser(
        id: 'u1',
        phone: '+9647701234567',
        name: name,
        roles: const ['RIDER'],
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
          child: SettingsScreen(appVersion: '0.1.0', onLogout: () async {}),
        ),
      ),
    );

AppSegmentedControl<ThemeMode> _control(WidgetTester t) =>
    t.widget<AppSegmentedControl<ThemeMode>>(
      find.byWidgetPredicate((w) => w is AppSegmentedControl<ThemeMode>),
    );

void main() {
  testWidgets('theme selector reflects the ThemeController and sets it',
      (t) async {
    final theme =
        ThemeController(store: InMemoryThemeModeStore()); // default: system
    final auth =
        AuthController(api: const _FakeAuthApi(), tokenStore: InMemoryTokenStore());
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
      api: const _FakeAuthApi(),
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
