import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import 'app_notification.dart';
import 'notifications_controller.dart';

/// Surfaces events that arrive **while the app is open**.
///
/// A list entry and a badge are enough for something you will read later. They
/// are not enough for something that changes what you should do in the next
/// two minutes, and the whole reason this work exists is that a driver could
/// cancel a trip and the rider found out by arriving at the pickup point.
///
/// So arrivals are split by [NotificationUrgency]:
///
///  * **toast** — a Masar-styled banner that slides in over the content and
///    goes away by itself. Cheap, ignorable, correct for "your booking is
///    confirmed".
///  * **blocking** — a dialog that cannot be dismissed by tapping outside or
///    by the back button, with one button to acknowledge. Currently only a
///    driver-cancelled trip. It interrupts because the alternative is that the
///    rider does not find out.
///
/// Mount this ONCE, above the navigator, so an event is announced whichever
/// screen the user is on.
class NotificationAnnouncer extends StatefulWidget {
  const NotificationAnnouncer({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationAnnouncer> createState() => _NotificationAnnouncerState();
}

class _NotificationAnnouncerState extends State<NotificationAnnouncer> {
  NotificationsController? _controller;

  /// One announcement at a time: two blocking dialogs stacked on top of each
  /// other would need two acknowledgements to reach the app, and the second
  /// one would look like the first failed to work.
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<NotificationsController>();
    if (identical(c, _controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = c..addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted || _showing) return;
    final pending = _controller?.drainPending() ?? const [];
    if (pending.isEmpty) return;
    // Deferred: this fires from a notifyListeners() that may itself be inside
    // a build, and showDialog during build throws.
    //
    // scheduleFrame() is not redundant. addPostFrameCallback only queues the
    // callback — it does not ask for a frame — so without this the announcement
    // would wait for someone else to schedule one. Today the nav badge watches
    // this controller and would, but "the cancellation dialog appears because
    // an unrelated badge happens to rebuild" is not a dependency worth having.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _announce(pending))
      ..scheduleFrame();
  }

  Future<void> _announce(List<AppNotification> pending) async {
    if (!mounted || _showing) return;
    _showing = true;
    try {
      // Blocking events first regardless of arrival order: if a cancellation
      // and a confirmation land in the same poll, the cancellation is the one
      // that must not be queued behind anything.
      final ordered = [
        ...pending.where((n) => n.type.urgency == NotificationUrgency.blocking),
        ...pending.where((n) => n.type.urgency != NotificationUrgency.blocking),
      ];
      for (final n in ordered) {
        if (!mounted) return;
        if (n.type.urgency == NotificationUrgency.blocking) {
          await showBlockingNotification(context, n);
          await _controller?.markRead(n.id);
        } else {
          _showToast(n);
          // Only the first toast of a batch is shown; the rest are already in
          // the centre and stacking banners would bury the screen.
          break;
        }
      }
    } finally {
      _showing = false;
    }
    // A poll can land while a dialog is open, and its events were left queued.
    // Without this they would wait for the *next* poll — up to another 30
    // seconds before a rider learns a second trip was cancelled.
    if (mounted) _onChanged();
  }

  void _showToast(AppNotification n) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final colors = context.colors;
    messenger
      ..hideCurrentMaterialBanner()
      ..showSnackBar(
        SnackBar(
          backgroundColor: colors.textPrimary,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(AppIcons.bell, size: context.space.lg, color: colors.background),
              SizedBox(width: context.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(n.title,
                        style: context.text.bodyStrong
                            .copyWith(color: colors.background)),
                    Text(n.body,
                        style: context.text.caption
                            .copyWith(color: colors.background),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The unmissable one.
///
/// `barrierDismissible: false` plus a [PopScope] that blocks the back button:
/// the only way past it is the acknowledge button. That is deliberate and it
/// is the point — a rider whose trip was cancelled must not be able to swipe
/// this away by reflex and walk to a pickup point anyway.
Future<void> showBlockingNotification(
  BuildContext context,
  AppNotification notification,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: BlockingNotificationDialog(
        notification: notification,
        onAcknowledge: () => Navigator.of(ctx).pop(),
      ),
    ),
  );
}

/// The body of a blocking notification, without the barrier around it.
///
/// Separate from [showBlockingNotification] so it can be rendered on its own in
/// a golden — the thing that must be reviewable is what this says and how it
/// looks, not the scrim.
class BlockingNotificationDialog extends StatelessWidget {
  const BlockingNotificationDialog({
    super.key,
    required this.notification,
    this.onAcknowledge,
  });

  final AppNotification notification;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: context.radii.cardAll),
      title: Row(
        children: [
          Container(
            width: space.xl2,
            height: space.xl2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Opaque tonal: its contrast must not depend on the scrim behind
              // it.
              color: colors.dangerTonal,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.warning, size: space.lg, color: colors.danger),
          ),
          SizedBox(width: space.md),
          Expanded(
            child: Text(
              notification.title,
              style: context.text.title.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
      content: Text(
        notification.body,
        style: context.text.body.copyWith(color: colors.textSecondary),
      ),
      actions: [
        AppButton(label: 'حسناً، فهمت', onPressed: onAcknowledge),
      ],
    );
  }
}
