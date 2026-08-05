/// What happened. Mirrors the backend `NotificationType` enum.
///
/// [unknown] is not a defect — it is how an old app survives a server that
/// learned a new event. An unrecognised notification still shows its title and
/// body (both composed server-side and already in Arabic); only the icon and
/// the severity fall back.
enum AppNotificationType {
  bookingCreated,
  bookingConfirmed,
  bookingCancelledByRider,
  bookingCancelled,
  tripStarted,
  tripCompleted,
  tripCancelled,
  driverApproved,
  driverRejected,
  unknown,
}

AppNotificationType notificationTypeFrom(String? raw) => switch (raw) {
      'BOOKING_CREATED' => AppNotificationType.bookingCreated,
      'BOOKING_CONFIRMED' => AppNotificationType.bookingConfirmed,
      'BOOKING_CANCELLED_BY_RIDER' => AppNotificationType.bookingCancelledByRider,
      'BOOKING_CANCELLED' => AppNotificationType.bookingCancelled,
      'TRIP_STARTED' => AppNotificationType.tripStarted,
      'TRIP_COMPLETED' => AppNotificationType.tripCompleted,
      'TRIP_CANCELLED' => AppNotificationType.tripCancelled,
      'DRIVER_APPROVED' => AppNotificationType.driverApproved,
      'DRIVER_REJECTED' => AppNotificationType.driverRejected,
      _ => AppNotificationType.unknown,
    };

/// How loudly an event has to arrive while the app is open.
enum NotificationUrgency {
  /// Slides in, slides away. The user loses nothing by missing it.
  toast,

  /// **Stops the app until acknowledged.** Reserved for events where missing
  /// it costs the user a journey.
  blocking,
}

extension AppNotificationTypeX on AppNotificationType {
  /// The one event that gets a blocking acknowledgement.
  ///
  /// A driver cancelling a trip the rider has booked is the only message here
  /// that, if missed, sends someone to stand on a street corner waiting for a
  /// car that is never coming. A toast that slides away after four seconds is
  /// not good enough for that, and everything else is not important enough to
  /// interrupt for — a rule that only holds while the exception stays rare.
  NotificationUrgency get urgency => this == AppNotificationType.tripCancelled
      ? NotificationUrgency.blocking
      : NotificationUrgency.toast;
}

/// One stored event for this user (GET /notifications).
///
/// [title] and [body] are composed server-side and arrive ready to render, so
/// the centre never re-derives copy from ids whose rows may since have changed
/// — a cancelled trip's notification must still read correctly after the trip
/// is gone.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.tripId,
    this.bookingId,
    this.readAt,
  });

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? tripId;
  final String? bookingId;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        tripId: tripId,
        bookingId: bookingId,
        readAt: readAt ?? this.readAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: notificationTypeFrom(json['type'] as String?),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        tripId: json['tripId'] as String?,
        bookingId: json['bookingId'] as String?,
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
      );
}

/// The centre's payload: the list and the badge, from one request.
class NotificationFeed {
  const NotificationFeed({required this.unreadCount, required this.notifications});

  static const empty = NotificationFeed(unreadCount: 0, notifications: []);

  final int unreadCount;
  final List<AppNotification> notifications;

  factory NotificationFeed.fromJson(Map<String, dynamic> json) => NotificationFeed(
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        notifications: ((json['notifications'] as List<dynamic>?) ?? const [])
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
