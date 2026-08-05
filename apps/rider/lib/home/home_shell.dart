import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../booking/booking_api.dart';
import '../booking/my_bookings_controller.dart';
import '../booking/my_bookings_screen.dart';
import '../config/app_config.dart';
import '../trip/search_screen.dart';

/// The authenticated home: a four-tab shell (ابحث · حجوزاتي · الإشعارات ·
/// حسابي). Each tab keeps its own state across switches (an [IndexedStack]);
/// the bookings tab owns its [MyBookingsController]; the account tab is the
/// shared Settings.
///
/// ## Why each tab is wrapped in a TickerMode
///
/// An [IndexedStack] keeps every tab mounted and building, so a polling screen
/// on an unselected tab would keep polling forever. `TickerMode` is Flutter's
/// existing answer to "should time-based work run in this subtree", and
/// [PollingScope] reads it — so flipping it here is what actually stops the
/// حجوزاتي poll while the rider is on the search tab.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Index of the حجوزاتي tab — where every booking- and trip-shaped event is
  /// actionable, including «انتهت رحلتك» and the rate action it leads to.
  static const int _bookingsTab = 1;

  /// Where a tapped notification takes the rider.
  ///
  /// Everything about a booking or a trip lands on حجوزاتي: the confirmation,
  /// the start, the cancellation, and — the one that had nowhere to go until
  /// now — the completion, whose whole point is to reach the rate action.
  /// A driver-approval event concerns the driver app and stays put.
  void _openNotification(AppNotification n) {
    switch (n.type) {
      case AppNotificationType.bookingConfirmed:
      case AppNotificationType.bookingCancelled:
      case AppNotificationType.tripStarted:
      case AppNotificationType.tripCompleted:
      case AppNotificationType.tripCancelled:
        setState(() => _index = _bookingsTab);
      case AppNotificationType.bookingCreated:
      case AppNotificationType.bookingCancelledByRider:
      case AppNotificationType.driverApproved:
      case AppNotificationType.driverRejected:
      case AppNotificationType.unknown:
        break; // not a rider-side destination
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      // The pill floats over the content rather than sitting in a bar, so the
      // body reserves its footprint and the nav is stacked on top.
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              bottom: FloatingPillNav.reservedSpace,
            ),
            child: IndexedStack(
              index: _index,
              children: [
                _Tab(selected: _index == 0, child: const SearchScreen()),
                _Tab(
                  selected: _index == 1,
                  child: ChangeNotifierProvider<MyBookingsController>(
                    create: (ctx) =>
                        MyBookingsController(api: ctx.read<BookingApi>()),
                    child: const MyBookingsScreen(),
                  ),
                ),
                _Tab(
                  selected: _index == 2,
                  child: NotificationsScreen(onOpen: _openNotification),
                ),
                _Tab(
                  selected: _index == 3,
                  child: SettingsScreen(
                    appVersion: AppConfig.appVersion,
                    onLogout: () => context.read<AuthController>().logout(),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingPillNav(
              currentIndex: _index,
              onSelect: (i) => setState(() => _index = i),
              items: [
                const FloatingPillNavItem(
                    icon: AppIcons.search, label: 'ابحث'),
                const FloatingPillNavItem(
                    icon: AppIcons.seat, label: 'حجوزاتي'),
                FloatingPillNavItem(
                  icon: AppIcons.bell,
                  label: 'إشعارات',
                  badgeCount: context.watch<NotificationsController>().unreadCount,
                ),
                const FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab of the [IndexedStack], with its time-based work gated on being the
/// selected one. See the class doc above.
class _Tab extends StatelessWidget {
  const _Tab({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: selected, child: child);
}
