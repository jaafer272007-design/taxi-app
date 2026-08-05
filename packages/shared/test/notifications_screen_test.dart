import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/notification_fakes.dart';

/// The notification centre: what it renders, what a tap does, and the numerals
/// rule (a `·` next to an Arabic-Indic digit reads as an extra zero).
void main() {
  Widget host(NotificationsController c) => ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: NotificationsScreen(),
          ),
        ),
      );

  /// A phone-sized surface: the default 800×600 test window is wider than any
  /// screen this app runs on, and the cards lay out differently there.
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('renders the inbox newest first with a mark-all row', (t) async {
    phone(t);
    final api = FakeNotificationApi(
      feed: feedOf([
        notif(
          id: 'n1',
          type: AppNotificationType.tripCancelled,
          title: 'أُلغيت رحلتك',
          body: 'ألغى السائق هذه الرحلة. حجزك لم يعد قائماً.',
        ),
        notif(id: 'n2', title: 'تم تأكيد حجزك'),
        notif(
          id: 'n3',
          title: 'انطلقت الرحلة',
          readAt: DateTime.utc(2026, 8, 5, 10),
        ),
      ]),
    );
    final c = NotificationsController(api: api);
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.text('أُلغيت رحلتك'), findsOneWidget);
    expect(find.text('تم تأكيد حجزك'), findsOneWidget);
    expect(find.text('انطلقت الرحلة'), findsOneWidget);
    // Two unread → the Arabic dual, which carries no digit at all.
    expect(find.text('لديك إشعاران جديدان'), findsOneWidget);
    expect(find.text('تعليم الكل كمقروء'), findsOneWidget);
  });

  testWidgets('the unread line uses Arabic-Indic digits from three up',
      (t) async {
    phone(t);
    final c = NotificationsController(
      api: FakeNotificationApi(
        feed: feedOf([notif(id: 'n1'), notif(id: 'n2'), notif(id: 'n3')]),
      ),
    );
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    expect(find.text('لديك ٣ إشعارات جديدة'), findsOneWidget);
  });

  testWidgets('never puts a dot beside an Arabic-Indic numeral', (t) async {
    phone(t);
    // `٠` IS a dot: `... · ٣ إشعارات` renders as «٣٠ إشعارات». The timestamp
    // line is the risk here — it joins a day and a zero-padded clock, and a
    // bare separator next to «٠٨:٤٥» reads as an extra zero. Three unread so
    // the count line actually carries a digit (the dual «إشعاران» does not).
    final c = NotificationsController(
      api: FakeNotificationApi(
        feed: feedOf([
          notif(id: 'n1', createdAt: DateTime.utc(2026, 8, 5, 5, 45)),
          notif(id: 'n2', createdAt: DateTime.utc(2026, 8, 5, 6, 0)),
          notif(id: 'n3', createdAt: DateTime.utc(2026, 8, 5, 7, 5)),
        ]),
      ),
    );
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    final offenders = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
        .toList();

    expect(offenders, isEmpty,
        reason: 'a middle dot touches an Arabic-Indic digit');
  });

  testWidgets('tapping an unread row marks it read; a read row is inert',
      (t) async {
    phone(t);
    final api = FakeNotificationApi(
      feed: feedOf([
        notif(id: 'n1', title: 'تم تأكيد حجزك'),
        notif(
          id: 'n2',
          title: 'انطلقت الرحلة',
          readAt: DateTime.utc(2026, 8, 5, 10),
        ),
      ]),
    );
    final c = NotificationsController(api: api);
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    await t.tap(find.text('تم تأكيد حجزك'));
    await t.pumpAndSettle();
    expect(api.markedRead, ['n1']);
    expect(c.unreadCount, 0);

    // Already read: AppCard.onTap is null, so this tap reaches nothing.
    await t.tap(find.text('انطلقت الرحلة'));
    await t.pumpAndSettle();
    expect(api.markedRead, ['n1']);
  });

  testWidgets('mark-all clears the badge and the row disappears', (t) async {
    phone(t);
    final api = FakeNotificationApi(
      feed: feedOf([notif(id: 'n1'), notif(id: 'n2')]),
    );
    final c = NotificationsController(api: api);
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    await t.tap(find.text('تعليم الكل كمقروء'));
    await t.pumpAndSettle();

    expect(api.markAllCalls, 1);
    expect(c.unreadCount, 0);
    expect(find.text('تعليم الكل كمقروء'), findsNothing);
  });

  testWidgets('an empty inbox explains itself', (t) async {
    phone(t);
    final c = NotificationsController(api: FakeNotificationApi());
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    expect(find.text('لا توجد إشعارات'), findsOneWidget);
    expect(find.text('سنخبرك هنا بكل ما يخص رحلاتك وحجوزاتك.'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry that works', (t) async {
    phone(t);
    final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]))
      ..failList = true;
    final c = NotificationsController(api: api);
    addTearDown(c.dispose);

    await t.pumpWidget(host(c));
    await t.pumpAndSettle();

    expect(find.text('لا يوجد اتصال بالإنترنت.'), findsOneWidget);

    api.failList = false;
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();

    expect(find.text('تم تأكيد حجزك'), findsOneWidget);
  });
}
