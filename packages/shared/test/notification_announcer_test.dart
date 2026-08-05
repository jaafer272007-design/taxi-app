import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/notification_fakes.dart';

/// [NotificationAnnouncer]: what an event does while the app is OPEN.
///
/// The distinction under test is the whole reason this exists — a confirmation
/// may slide away unseen, a driver-cancelled trip may not. Someone who misses
/// the cancellation walks to a pickup point for a car that is not coming.
void main() {
  Widget host(NotificationsController c) => ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: NotificationAnnouncer(
              child: Scaffold(body: Center(child: Text('الرئيسية'))),
            ),
          ),
        ),
      );

  AppNotification cancellation({String id = 'c1'}) => notif(
        id: id,
        type: AppNotificationType.tripCancelled,
        title: 'أُلغيت رحلتك',
        body: 'ألغى السائق هذه الرحلة. حجزك لم يعد قائماً — ابحث عن رحلة أخرى.',
      );

  /// Mount the announcer and let the app-shell's first poll seed the inbox —
  /// the real startup order, with the announcer already listening while that
  /// first feed lands.
  Future<NotificationsController> seeded(
    WidgetTester t,
    FakeNotificationApi api,
  ) async {
    final c = NotificationsController(api: api);
    addTearDown(c.dispose);
    await t.pumpWidget(host(c));
    await c.refreshSilently();
    await t.pumpAndSettle();
    return c;
  }

  /// Unmount, which disposes the ScaffoldMessenger and with it the snack bar's
  /// auto-dismiss timer. flutter_test fails on a pending one.
  Future<void> unmount(WidgetTester t) => t.pumpWidget(const SizedBox.shrink());

  testWidgets('a cancelled trip blocks the app until acknowledged', (t) async {
    final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
    final c = await seeded(t, api);

    api.feed = feedOf([cancellation(), notif(id: 'n1')]);
    await c.refreshSilently();
    await t.pumpAndSettle();

    expect(find.text('أُلغيت رحلتك'), findsOneWidget);
    expect(find.text('حسناً، فهمت'), findsOneWidget);

    // Tapping the barrier must not get rid of it.
    await t.tapAt(const Offset(8, 8));
    await t.pumpAndSettle();
    expect(find.text('أُلغيت رحلتك'), findsOneWidget,
        reason: 'this one may not be swiped away by reflex');

    // Nor the Android back button: the dialog is wrapped in a PopScope that
    // refuses. (Asserting the wrapper rather than faking a system pop — every
    // public way to do the latter is deprecated or @protected.)
    final scope = t.widget<PopScope<dynamic>>(
      find
          .ancestor(
            of: find.byType(AlertDialog),
            matching: find.byType(PopScope<dynamic>),
          )
          .first,
    );
    expect(scope.canPop, isFalse);

    // The one way out — and taking it marks the event read.
    await t.tap(find.text('حسناً، فهمت'));
    await t.pumpAndSettle();
    expect(find.text('أُلغيت رحلتك'), findsNothing);
    expect(api.markedRead, ['c1']);

    await unmount(t);
  });

  testWidgets('an ordinary event is a toast, not an interruption', (t) async {
    final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
    final c = await seeded(t, api);

    api.feed = feedOf([
      notif(id: 'n2', title: 'تم تأكيد حجزك', body: 'مقعدك محجوز.'),
      notif(id: 'n1'),
    ]);
    await c.refreshSilently();
    await t.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('تم تأكيد حجزك'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // A toast is a courtesy, not an acknowledgement: it must not silently
    // clear the badge the user has not looked at yet.
    expect(api.markedRead, isEmpty);
    expect(c.unreadCount, 2);

    await unmount(t);
  });

  testWidgets('the cancellation is shown first when both land in one poll',
      (t) async {
    final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
    final c = await seeded(t, api);

    // Server order is newest first, and the confirmation is the newer row —
    // so arrival order alone would put the cancellation second.
    api.feed = feedOf([
      notif(id: 'n3', title: 'تم تأكيد حجزك'),
      cancellation(),
      notif(id: 'n1'),
    ]);
    await c.refreshSilently();
    await t.pumpAndSettle();

    expect(find.text('أُلغيت رحلتك'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'nothing queues in front of a cancellation');

    await t.tap(find.text('حسناً، فهمت'));
    await t.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('تم تأكيد حجزك'), findsOneWidget);

    await unmount(t);
  });

  testWidgets('the inbox already on screen at startup is not replayed',
      (t) async {
    final api = FakeNotificationApi(
      feed: feedOf([cancellation(), notif(id: 'n1'), notif(id: 'n2')]),
    );
    await seeded(t, api);
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'opening the app must not re-announce last week');
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('الرئيسية'), findsOneWidget);

    await unmount(t);
  });

  testWidgets('an event that arrives already read is not announced', (t) async {
    final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
    final c = await seeded(t, api);

    // Read on the other device, or by a push tap.
    api.feed = feedOf([
      notif(id: 'n2', readAt: DateTime.utc(2026, 8, 5, 11)),
      notif(id: 'n1'),
    ]);
    await c.refreshSilently();
    await t.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await unmount(t);
  });

  testWidgets('a second cancellation arriving mid-dialog is not lost',
      (t) async {
    final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
    final c = await seeded(t, api);

    api.feed = feedOf([cancellation(), notif(id: 'n1')]);
    await c.refreshSilently();
    await t.pumpAndSettle();
    expect(find.text('أُلغيت رحلتك'), findsOneWidget);

    // A poll lands while the driver's first cancellation is still on screen.
    api.feed = feedOf([
      notif(
        id: 'c2',
        type: AppNotificationType.tripCancelled,
        title: 'أُلغيت رحلة أخرى',
        body: 'ألغى السائق هذه الرحلة أيضاً.',
      ),
      cancellation(),
      notif(id: 'n1'),
    ]);
    await c.refreshSilently();
    await t.pumpAndSettle();

    await t.tap(find.text('حسناً، فهمت'));
    await t.pumpAndSettle();

    expect(find.text('أُلغيت رحلة أخرى'), findsOneWidget,
        reason: 'it must not wait for the next poll 30 seconds later');

    await t.tap(find.text('حسناً، فهمت'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await unmount(t);
  });
}
