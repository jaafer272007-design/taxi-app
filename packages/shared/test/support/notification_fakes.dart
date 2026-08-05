import 'package:shared/shared.dart';

/// A scriptable [NotificationApi]: the feed it returns can be swapped between
/// calls (that is how a poll "discovers" a new event), and each endpoint can be
/// made to fail independently.
class FakeNotificationApi implements NotificationApi {
  FakeNotificationApi({NotificationFeed? feed})
      : feed = feed ?? NotificationFeed.empty;

  /// What the next [list] returns. Reassign to simulate the server changing.
  NotificationFeed feed;

  bool failList = false;
  bool failMarkRead = false;
  bool failMarkAllRead = false;

  int listCalls = 0;
  final List<String> markedRead = [];
  int markAllCalls = 0;

  @override
  Future<NotificationFeed> list() async {
    listCalls++;
    if (failList) throw const ApiException('لا يوجد اتصال بالإنترنت.');
    return feed;
  }

  @override
  Future<void> markRead(String id) async {
    if (failMarkRead) throw const ApiException('تعذّر الاتصال.');
    markedRead.add(id);
  }

  @override
  Future<void> markAllRead() async {
    if (failMarkAllRead) throw const ApiException('تعذّر الاتصال.');
    markAllCalls++;
  }
}

/// One notification, with everything defaulted so a test names only what it
/// cares about.
AppNotification notif({
  required String id,
  AppNotificationType type = AppNotificationType.bookingConfirmed,
  String title = 'تم تأكيد حجزك',
  String body = 'مقعدك محجوز في رحلة النجف ← كربلاء.',
  DateTime? createdAt,
  DateTime? readAt,
  String? tripId,
  String? bookingId,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt ?? DateTime.utc(2026, 8, 5, 9, 30),
      readAt: readAt,
      tripId: tripId,
      bookingId: bookingId,
    );

/// A feed whose unread count is derived from the rows, which is what the server
/// does — a test that hand-picks a mismatching count is testing nothing.
NotificationFeed feedOf(List<AppNotification> items) => NotificationFeed(
      unreadCount: items.where((n) => n.isUnread).length,
      notifications: items,
    );
