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
  const _GoldenAuthApi({this.contact});

  /// Null renders the DEFAULT state — which is the one that matters most: a
  /// rider who never opts in must see an unobtrusive row and nothing else.
  final EmergencyContact? contact;

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
  Future<AuthUser> me() async => AuthUser(
        id: _user.id,
        phone: _user.phone,
        name: _user.name,
        gender: _user.gender,
        roles: _user.roles,
        profileComplete: _user.profileComplete,
        emergencyContact: contact,
      );
  @override
  Future<AuthUser> updateName(String name) async => _user;
  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async => _user;
  @override
  Future<AuthUser> updateEmergencyContact(EmergencyContact? c) async => _user;
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

  // The saved state, shot separately from the default one above. Both matter:
  // the empty card is what every rider sees and must stay quiet, and the filled
  // card is where a wrong number would be spotted — so the number has to be
  // legible, Western and LTR, in both themes.
  group('settings_emergency_contact', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'settings_emergency_light',
          brightness: Brightness.light,
          child: await _settings(ThemeMode.light, contact: _savedContact));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'settings_emergency_dark',
          brightness: Brightness.dark,
          child: await _settings(ThemeMode.dark, contact: _savedContact));
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
Future<Widget> _settings(ThemeMode mode, {EmergencyContact? contact}) async {
  final theme = ThemeController(store: InMemoryThemeModeStore(), initialMode: mode);
  final auth = AuthController(
    api: _GoldenAuthApi(contact: contact),
    tokenStore: InMemoryTokenStore('jwt'),
  );
  await auth.bootstrap();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<AuthController>.value(value: auth),
    ],
    child: SettingsScreen(
      appVersion: '0.1.0',
      onLogout: () async {},
      showEmergencyContact: true,
    ),
  );
}

const _savedContact =
    EmergencyContact(name: 'أم علي', phone: '+9647701112233');

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
