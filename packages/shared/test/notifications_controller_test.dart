import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/notification_fakes.dart';

/// [NotificationsController]: unread counting, what a poll is allowed to do to
/// the screen, and which arrivals reach the announcer.
void main() {
  group('loading and unread counting', () {
    test('first load fills the list and the badge', () async {
      final api = FakeNotificationApi(
        feed: feedOf([
          notif(id: 'n1'),
          notif(id: 'n2', readAt: DateTime.utc(2026, 8, 5, 10)),
          notif(id: 'n3'),
        ]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);

      await c.load();

      expect(c.status, NotificationsStatus.loaded);
      expect(c.items, hasLength(3));
      expect(c.unreadCount, 2, reason: 'n2 is already read');
      expect(c.isEmpty, isFalse);
    });

    test('an empty inbox is loaded, not an error', () async {
      final c = NotificationsController(api: FakeNotificationApi());
      addTearDown(c.dispose);

      await c.load();

      expect(c.status, NotificationsStatus.loaded);
      expect(c.isEmpty, isTrue);
      expect(c.unreadCount, 0);
      expect(c.error, isNull);
    });

    test('a visible load surfaces the Arabic error', () async {
      final api = FakeNotificationApi()..failList = true;
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);

      await c.load();

      expect(c.status, NotificationsStatus.error);
      expect(c.error, 'لا يوجد اتصال بالإنترنت.');
    });

    test('overlapping loads are dropped, not queued', () async {
      final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);

      await Future.wait([c.load(), c.load(), c.load()]);

      expect(api.listCalls, 1);
    });
  });

  group('a failed poll never disturbs the screen', () {
    test('keeps the list, the count and the loaded status', () async {
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1'), notif(id: 'n2')]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();
      expect(c.items, hasLength(2));

      // The connection drops mid-journey.
      api.failList = true;
      await c.refreshSilently();

      expect(c.items, hasLength(2), reason: 'a dropped packet must not empty the inbox');
      expect(c.unreadCount, 2);
      expect(c.status, NotificationsStatus.loaded);
      expect(c.error, isNull, reason: 'the user did not ask for this refresh');
    });

    test('a poll that fails before the first load leaves the screen alone',
        () async {
      final api = FakeNotificationApi()..failList = true;
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);

      await c.refreshSilently();

      expect(c.status, NotificationsStatus.loading);
      expect(c.error, isNull);
      // hasLoaded is what the centre asks before deciding to fetch: a failed
      // poll must leave it false so opening the tab does a VISIBLE load with a
      // spinner and a retry, instead of sitting on a spinner forever.
      expect(c.hasLoaded, isFalse);
    });

    test('a failed first poll does not turn the next one into an announcement '
        'storm', () async {
      // The regression this guards: `hasLoaded` used to be set by any finished
      // request, so one dropped poll on app open made the whole inbox "new"
      // and every unread row would have been toasted at once — with a blocking
      // dialog among them.
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1'), notif(id: 'n2'), notif(id: 'n3')]),
      )..failList = true;
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);

      await c.refreshSilently();
      api.failList = false;
      await c.refreshSilently();

      expect(c.items, hasLength(3));
      expect(c.drainPending(), isEmpty);
    });

    test('the next successful poll picks the data back up', () async {
      final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      api.failList = true;
      await c.refreshSilently();
      api.failList = false;
      api.feed = feedOf([notif(id: 'n2'), notif(id: 'n1')]);
      await c.refreshSilently();

      expect(c.items, hasLength(2));
      expect(c.unreadCount, 2);
    });
  });

  group('announcing arrivals', () {
    test('the first load announces nothing', () async {
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1'), notif(id: 'n2'), notif(id: 'n3')]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);

      await c.load();

      expect(c.drainPending(), isEmpty,
          reason: 'opening the app must not replay last week as a toast stack');
    });

    test('a poll announces only what is new and unread', () async {
      final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      api.feed = feedOf([
        notif(id: 'n3', type: AppNotificationType.tripCancelled),
        notif(id: 'n2', readAt: DateTime.utc(2026, 8, 5, 11)),
        notif(id: 'n1'),
      ]);
      await c.refreshSilently();

      final pending = c.drainPending();
      expect(pending.map((n) => n.id), ['n3'],
          reason: 'n1 was already seen and n2 arrived already read');
    });

    test('drained events are oldest first', () async {
      final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      // Server order is newest first; the announcer wants the reverse.
      api.feed = feedOf([notif(id: 'n3'), notif(id: 'n2'), notif(id: 'n1')]);
      await c.refreshSilently();

      expect(c.drainPending().map((n) => n.id), ['n2', 'n3']);
    });

    test('draining empties the queue — an event is announced once', () async {
      final api = FakeNotificationApi(feed: feedOf([notif(id: 'n1')]));
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      api.feed = feedOf([notif(id: 'n2'), notif(id: 'n1')]);
      await c.refreshSilently();
      expect(c.drainPending(), hasLength(1));

      // The same row comes back on every poll from now on.
      await c.refreshSilently();
      await c.refreshSilently();
      expect(c.drainPending(), isEmpty);
    });
  });

  group('marking read', () {
    test('markRead updates the row and the badge before the server answers',
        () async {
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1'), notif(id: 'n2')]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      final future = c.markRead('n1');
      expect(c.unreadCount, 1, reason: 'optimistic: no waiting for a round trip');
      expect(c.items.firstWhere((n) => n.id == 'n1').isUnread, isFalse);

      await future;
      expect(api.markedRead, ['n1']);
      expect(c.unreadCount, 1);
    });

    test('a failed markRead puts the unread state back', () async {
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1'), notif(id: 'n2')]),
      )..failMarkRead = true;
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      await c.markRead('n1');

      expect(c.unreadCount, 2,
          reason: 'a badge that vanished on a failed request hides the event');
      expect(c.items.firstWhere((n) => n.id == 'n1').isUnread, isTrue);
    });

    test('markRead on an already-read row does nothing', () async {
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1', readAt: DateTime.utc(2026, 8, 5, 10))]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      await c.markRead('n1');
      await c.markRead('nope');

      expect(api.markedRead, isEmpty);
      expect(c.unreadCount, 0);
    });

    test('markAllRead clears the badge and every row', () async {
      final api = FakeNotificationApi(
        feed: feedOf([
          notif(id: 'n1'),
          notif(id: 'n2'),
          notif(id: 'n3', readAt: DateTime.utc(2026, 8, 5, 10)),
        ]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      await c.markAllRead();

      expect(c.unreadCount, 0);
      expect(c.items.every((n) => !n.isUnread), isTrue);
      expect(api.markAllCalls, 1);
    });

    test('a failed markAllRead restores every row it cleared', () async {
      final api = FakeNotificationApi(
        feed: feedOf([
          notif(id: 'n1'),
          notif(id: 'n2'),
          notif(id: 'n3', readAt: DateTime.utc(2026, 8, 5, 10)),
        ]),
      )..failMarkAllRead = true;
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      await c.markAllRead();

      expect(c.unreadCount, 2);
      expect(c.items.where((n) => n.isUnread).map((n) => n.id), ['n1', 'n2']);
    });

    test('markAllRead with nothing unread does not call the server', () async {
      final api = FakeNotificationApi(
        feed: feedOf([notif(id: 'n1', readAt: DateTime.utc(2026, 8, 5, 10))]),
      );
      final c = NotificationsController(api: api);
      addTearDown(c.dispose);
      await c.load();

      await c.markAllRead();

      expect(api.markAllCalls, 0);
    });
  });

  group('parsing', () {
    test('an unknown server type still renders its Arabic copy', () {
      final n = AppNotification.fromJson(const {
        'id': 'n9',
        'type': 'SOMETHING_WE_SHIPPED_LATER',
        'title': 'عنوان',
        'body': 'نص',
        'createdAt': '2026-08-05T09:30:00.000Z',
      });

      expect(n.type, AppNotificationType.unknown);
      expect(n.title, 'عنوان');
      expect(n.isUnread, isTrue);
    });

    test('only a driver-cancelled trip blocks the app', () {
      for (final type in AppNotificationType.values) {
        expect(
          type.urgency,
          type == AppNotificationType.tripCancelled
              ? NotificationUrgency.blocking
              : NotificationUrgency.toast,
          reason: '$type',
        );
      }
    });
  });
}
