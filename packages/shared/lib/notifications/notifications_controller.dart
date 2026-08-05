import 'package:flutter/foundation.dart';

import '../net/api_exception.dart';
import 'app_notification.dart';
import 'notification_api.dart';

enum NotificationsStatus { loading, error, loaded }

/// The notification centre's state, and the source of the nav badge.
///
/// Lives at the app shell (not on the notifications screen) for two reasons:
/// the badge has to be correct on every tab, and the announcer has to see an
/// event arrive whichever screen the user happens to be on.
class NotificationsController extends ChangeNotifier {
  NotificationsController({required NotificationApi api}) : _api = api;

  final NotificationApi _api;

  NotificationsStatus _status = NotificationsStatus.loading;
  List<AppNotification> _items = const [];
  int _unreadCount = 0;
  String? _error;

  /// True once a feed has actually been absorbed — NOT "once a request
  /// finished". The first fetch in both apps is a background poll fired by the
  /// app-shell [PollingScope], and if that one fails on a bad connection the
  /// difference matters twice over: the centre would sit on a spinner with no
  /// retry, and the next successful poll would treat the whole inbox as new
  /// and announce a week of events at once.
  bool _hasLoaded = false;
  bool _inFlight = false;

  /// Ids already handed to the announcer, so an event is surfaced once and not
  /// again on every poll. Grows with the inbox, which is bounded by the
  /// server's page size.
  final Set<String> _announced = {};

  /// Events that arrived since the last time the announcer drained this.
  final List<AppNotification> _pending = [];

  NotificationsStatus get status => _status;
  List<AppNotification> get items => _items;
  int get unreadCount => _unreadCount;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  bool get isEmpty => _items.isEmpty;

  /// Take the newly-arrived events, oldest first, clearing the queue.
  ///
  /// A queue rather than a callback so a controller with no announcer attached
  /// (a test, a screen mounted early) does not silently drop events on the
  /// floor, and so the announcer can decide the order it shows them in.
  List<AppNotification> drainPending() {
    if (_pending.isEmpty) return const [];
    final out = List<AppNotification>.from(_pending.reversed);
    _pending.clear();
    return out;
  }

  /// Fetch the inbox.
  ///
  /// [silent] is what polling passes: on failure the previous list and count
  /// stay exactly as they were and no error is surfaced. That is the whole
  /// contract of a background refresh — the user did not ask for it and must
  /// not be told it failed.
  Future<void> load({bool silent = false}) async {
    if (_inFlight) return;
    _inFlight = true;
    if (!silent) {
      _status = NotificationsStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      final feed = await _api.list();
      _absorb(feed);
      _status = NotificationsStatus.loaded;
      _error = null;
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = NotificationsStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'تعذّر تحميل الإشعارات. حاول مرة أخرى.';
        _status = NotificationsStatus.error;
      }
    } finally {
      _inFlight = false;
      notifyListeners();
    }
  }

  /// A poll. Identical to [load] except it can never disturb the screen.
  Future<void> refreshSilently() => load(silent: true);

  void _absorb(NotificationFeed feed) {
    // The first feed seeds the "already seen" set WITHOUT announcing: opening
    // the app must not replay every notification from the last week as a stack
    // of toasts.
    final seeding = !_hasLoaded;
    _hasLoaded = true;
    for (final n in feed.notifications) {
      if (_announced.add(n.id) && !seeding && n.isUnread) {
        _pending.add(n);
      }
    }
    _items = feed.notifications;
    _unreadCount = feed.unreadCount;
  }

  /// Mark one read. Optimistic: the row and the badge update immediately and
  /// are reconciled by the next poll, because a tap that appears to do nothing
  /// for a whole network round trip reads as a broken list.
  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0 || !_items[index].isUnread) return;

    final previous = _items;
    final previousCount = _unreadCount;
    _items = [
      for (final n in _items)
        if (n.id == id) n.copyWith(readAt: DateTime.now()) else n,
    ];
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    notifyListeners();

    try {
      await _api.markRead(id);
    } catch (_) {
      // Put it back. An unread badge that vanished on a failed request would
      // hide the event permanently.
      _items = previous;
      _unreadCount = previousCount;
      notifyListeners();
    }
  }

  /// Mark everything read.
  Future<void> markAllRead() async {
    if (_unreadCount == 0) return;
    final previous = _items;
    final previousCount = _unreadCount;
    final now = DateTime.now();
    _items = [
      for (final n in _items) n.isUnread ? n.copyWith(readAt: now) : n,
    ];
    _unreadCount = 0;
    notifyListeners();

    try {
      await _api.markAllRead();
    } catch (_) {
      _items = previous;
      _unreadCount = previousCount;
      notifyListeners();
    }
  }
}
