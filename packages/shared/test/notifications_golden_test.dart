import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/notification_fakes.dart';

/// Golden tests for the notification centre and the blocking cancellation
/// dialog — BOTH light and dark, RTL, Arabic, real Cairo + Lucide, at a 390×844
/// phone frame. CI generates the PNGs and mirrors them into
/// `docs/ui-screenshots/` so they can be reviewed inline on a phone.
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

  group('notification centre', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'notifications_light',
          brightness: Brightness.light,
          child: await _centre());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'notifications_dark',
          brightness: Brightness.dark,
          child: await _centre());
    });
  });

  group('notification centre — empty', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'notifications_empty_light',
          brightness: Brightness.light,
          child: await _centre(empty: true));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'notifications_empty_dark',
          brightness: Brightness.dark,
          child: await _centre(empty: true));
    });
  });

  group('cancelled-trip dialog', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'notification_blocking_light',
          brightness: Brightness.light,
          child: _blocking());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'notification_blocking_dark',
          brightness: Brightness.dark,
          child: _blocking());
    });
  });
}

/// The inbox with one of each tone: a cancellation (danger), a confirmation
/// (success), a departure (info) and an already-read row that recedes.
///
/// Three unread on purpose — the mark-all line then carries an actual digit
/// («لديك ٣ إشعارات جديدة»), which is where the ٠-as-a-dot hazard would show.
Future<Widget> _centre({bool empty = false}) async {
  final api = FakeNotificationApi(
    feed: empty
        ? NotificationFeed.empty
        : feedOf([
            notif(
              id: 'n1',
              type: AppNotificationType.tripCancelled,
              title: 'أُلغيت رحلتك',
              body: 'ألغى السائق هذه الرحلة. حجزك لم يعد قائماً — ابحث عن رحلة أخرى.',
              createdAt: DateTime.utc(2026, 8, 5, 5, 45),
            ),
            notif(
              id: 'n2',
              type: AppNotificationType.bookingConfirmed,
              title: 'تم تأكيد حجزك',
              body: 'مقعدك محجوز في رحلة النجف ← كربلاء مع علي حسن.',
              createdAt: DateTime.utc(2026, 8, 5, 4, 10),
            ),
            notif(
              id: 'n3',
              type: AppNotificationType.tripStarted,
              title: 'انطلقت رحلتك',
              body: 'السائق في الطريق إلى نقطة الانطلاق.',
              createdAt: DateTime.utc(2026, 8, 4, 14, 0),
            ),
            notif(
              id: 'n4',
              type: AppNotificationType.tripCompleted,
              title: 'انتهت رحلتك',
              body: 'نتمنى أن تكون رحلة موفقة. قيّم السائق من «حجوزاتي».',
              createdAt: DateTime.utc(2026, 8, 4, 11, 30),
              readAt: DateTime.utc(2026, 8, 4, 12),
            ),
          ]),
  );
  final c = NotificationsController(api: api);
  await c.load();
  return ChangeNotifierProvider<NotificationsController>.value(
    value: c,
    child: const NotificationsScreen(),
  );
}

Widget _blocking() => Center(
      child: BlockingNotificationDialog(
        notification: notif(
          id: 'c1',
          type: AppNotificationType.tripCancelled,
          title: 'أُلغيت رحلتك',
          body: 'ألغى السائق هذه الرحلة. حجزك لم يعد قائماً — ابحث عن رحلة أخرى.',
        ),
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
