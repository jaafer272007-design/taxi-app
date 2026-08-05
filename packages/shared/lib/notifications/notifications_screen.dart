import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format/numerals.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_scaffold.dart';
import 'app_notification.dart';
import 'notifications_controller.dart';

/// "الإشعارات" — everything that happened to this user, newest first.
///
/// Shared by both apps: the inbox is the same surface, and which events land
/// in it is decided server-side by who the event was for. Unread rows carry a
/// pine dot and a tonal fill so the eye finds them before it reads anything.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<NotificationsController>();
      if (!c.hasLoaded) c.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();

    return AppScaffold(
      title: 'الإشعارات',
      padded: false,
      body: switch (c.status) {
        NotificationsStatus.loading =>
          Center(child: CircularProgressIndicator(color: context.colors.primary)),
        NotificationsStatus.error => _ErrorView(
            message: c.error ?? 'حدث خطأ. حاول مرة أخرى.',
            onRetry: c.load,
          ),
        NotificationsStatus.loaded =>
          c.isEmpty ? const _EmptyView() : _NotificationsList(controller: c),
      },
    );
  }
}

class _NotificationsList extends StatelessWidget {
  const _NotificationsList({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final items = controller.items;

    return RefreshIndicator(
      color: context.colors.primary,
      // Silent: the indicator IS the spinner, and a non-silent load would flip
      // the screen back to its loading state and take the list away mid-pull.
      onRefresh: controller.refreshSilently,
      child: ListView.separated(
        padding: EdgeInsets.all(space.lg),
        // +1 for the "mark all read" header when there is anything unread.
        itemCount: items.length + (controller.unreadCount > 0 ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: space.sm),
        itemBuilder: (_, i) {
          if (controller.unreadCount > 0 && i == 0) {
            return _MarkAllRow(controller: controller);
          }
          final n = items[controller.unreadCount > 0 ? i - 1 : i];
          return _NotificationCard(
            notification: n,
            onTap: () => controller.markRead(n.id),
          );
        },
      ),
    );
  }
}

/// "لديك ٣ إشعارات جديدة" + a one-tap clear.
class _MarkAllRow extends StatelessWidget {
  const _MarkAllRow({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.only(bottom: space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // «إشعار جديد» carries no digit at 1, and at 3+ the digit leads
              // the phrase — no separator anywhere near it. See the numerals
              // rule in CLAUDE.md.
              _unreadPhrase(controller.unreadCount),
              style: context.text.label.copyWith(color: colors.textSecondary),
            ),
          ),
          AppButton(
            label: 'تعليم الكل كمقروء',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            expand: false,
            onPressed: controller.markAllRead,
          ),
        ],
      ),
    );
  }
}

/// Arabic plural agreement for the unread line.
String _unreadPhrase(int count) => switch (count) {
      1 => 'لديك إشعار جديد',
      2 => 'لديك إشعاران جديدان',
      _ => 'لديك ${formatCount(count)} إشعارات جديدة',
    };

/// One event. Unread rows are tonal with a leading dot; read rows recede.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final unread = notification.isUnread;
    final tone = _toneFor(notification.type, colors);

    return AppCard(
      onTap: unread ? onTap : null,
      muted: !unread,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: space.xl2,
            height: space.xl2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Opaque tonal, never an alpha tint — this card sits on the page
              // background here and on a muted card when read.
              color: _tonalFor(notification.type, colors),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(notification.type), size: space.lg, color: tone),
          ),
          SizedBox(width: space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: unread
                            ? context.text.bodyStrong
                                .copyWith(color: colors.textPrimary)
                            : context.text.body
                                .copyWith(color: colors.textSecondary),
                      ),
                    ),
                    if (unread) ...[
                      SizedBox(width: space.sm),
                      Padding(
                        padding: EdgeInsets.only(top: space.xs),
                        child: Container(
                          width: space.sm,
                          height: space.sm,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: space.xs),
                Text(
                  notification.body,
                  style: context.text.body.copyWith(color: colors.textSecondary),
                ),
                SizedBox(height: space.xs),
                Text(
                  // «الساعة» between the day and the clock: a bare separator
                  // beside «٠٨:٤٥» would read as an extra zero.
                  '${formatDayShortBaghdad(notification.createdAt)} '
                  'الساعة ${formatTime(notification.createdAt)}',
                  style: context.text.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(AppNotificationType type) => switch (type) {
      AppNotificationType.bookingCreated => AppIcons.seat,
      AppNotificationType.bookingConfirmed => AppIcons.success,
      AppNotificationType.bookingCancelledByRider => AppIcons.close,
      AppNotificationType.bookingCancelled => AppIcons.close,
      AppNotificationType.tripStarted => AppIcons.car,
      AppNotificationType.tripCompleted => AppIcons.check,
      AppNotificationType.tripCancelled => AppIcons.warning,
      AppNotificationType.driverApproved => AppIcons.success,
      AppNotificationType.driverRejected => AppIcons.warning,
      AppNotificationType.unknown => AppIcons.bell,
    };

Color _toneFor(AppNotificationType type, AppColors c) => switch (type) {
      AppNotificationType.tripCancelled ||
      AppNotificationType.driverRejected =>
        c.danger,
      AppNotificationType.bookingCancelled ||
      AppNotificationType.bookingCancelledByRider =>
        c.warning,
      AppNotificationType.bookingConfirmed ||
      AppNotificationType.tripCompleted ||
      AppNotificationType.driverApproved =>
        c.success,
      _ => c.info,
    };

Color _tonalFor(AppNotificationType type, AppColors c) => switch (type) {
      AppNotificationType.tripCancelled ||
      AppNotificationType.driverRejected =>
        c.dangerTonal,
      AppNotificationType.bookingCancelled ||
      AppNotificationType.bookingCancelledByRider =>
        c.warningTonal,
      AppNotificationType.bookingConfirmed ||
      AppNotificationType.tripCompleted ||
      AppNotificationType.driverApproved =>
        c.successTonal,
      _ => c.infoTonal,
    };

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2,
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryTonal,
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.bell, color: colors.primary, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text('لا توجد إشعارات',
                style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.sm),
            Text('سنخبرك هنا بكل ما يخص رحلاتك وحجوزاتك.',
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
            SizedBox(height: space.lg),
            Text(message, style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.xl),
            AppButton(
              label: 'إعادة المحاولة',
              expand: false,
              onPressed: () => onRetry(),
            ),
          ],
        ),
      ),
    );
  }
}
