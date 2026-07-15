import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Golden tests for the shared Settings screen + the logout confirm dialog,
/// BOTH light and dark, RTL, Arabic, real Cairo + Lucide fonts, at a 390×844
/// phone frame. CI generates the PNGs and mirrors them to docs/ui-screenshots/.
class _GoldenAuthApi implements AuthApi {
  const _GoldenAuthApi();

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
  Future<AuthUser> me() async => _user;
  @override
  Future<AuthUser> updateName(String name) async => _user;
  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async => _user;
}

void main() {
  setUpAll(() async {
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(
              rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf')))
        .load();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.light();
    AppTheme.dark();
    await GoogleFonts.pendingFonts();
  });

  group('settings', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'settings_light',
          brightness: Brightness.light,
          child: await _settings(ThemeMode.light));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'settings_dark',
          brightness: Brightness.dark,
          child: await _settings(ThemeMode.dark));
    });
  });

  group('logout_confirm', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'logout_confirm_light',
          brightness: Brightness.light,
          child: _logoutDialog());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'logout_confirm_dark',
          brightness: Brightness.dark,
          child: _logoutDialog());
    });
  });
}

/// Settings screen with a signed-in user and [mode] pre-selected in the theme
/// segmented control.
Future<Widget> _settings(ThemeMode mode) async {
  final theme = ThemeController(store: InMemoryThemeModeStore(), initialMode: mode);
  final auth = AuthController(
    api: const _GoldenAuthApi(),
    tokenStore: InMemoryTokenStore('jwt'),
  );
  await auth.bootstrap();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<AuthController>.value(value: auth),
    ],
    child: SettingsScreen(appVersion: '0.1.0', onLogout: () async {}),
  );
}

Widget _logoutDialog() => const Center(
      child: AppConfirmDialog(
        title: 'تسجيل الخروج؟',
        message: 'سيتم إنهاء جلستك على هذا الجهاز. يمكنك الدخول مجدداً في أي وقت.',
        confirmLabel: 'تسجيل الخروج',
        confirmVariant: AppButtonVariant.danger,
      ),
    );

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
}) async {
  const width = 390.0;
  const height = 844.0;
  const dpr = 2.0;
  tester.view.physicalSize = const Size(width * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme =
      brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );

  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
