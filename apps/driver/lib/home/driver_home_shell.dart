import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../config/app_config.dart';
import '../earnings/earnings_controller.dart';
import '../earnings/earnings_screen.dart';
import '../pool/pool_api.dart';
import '../pool/pool_board_controller.dart';
import '../trip/driver_trip_api.dart';
import '../trip/my_trips_controller.dart';
import '../trip/my_trips_screen.dart';
import '../trip/post_trip_controller.dart';
import 'get_work_screen.dart';

/// The APPROVED driver's home: a five-tab shell (العمل · رحلاتي · أرباحي ·
/// إشعارات · حسابي). Owns the post-trip, my-trips, board and earnings
/// controllers; the account tab is the shared Settings. Seat count is capped at
/// [vehicleSeats].
///
/// Five tabs is the pill's documented maximum — [FloatingPillNav] asserts it —
/// and that constraint is why Phase 2's pool board is a segment INSIDE the
/// first tab rather than a sixth destination. It turned out to be the better
/// model anyway: posting a trip and claiming a pool are two answers to one
/// question ("how do I fill this morning?"), so they belong on one surface
/// where the driver can compare them, not in two places they have to remember
/// to check.
///
/// Each tab is wrapped in a `TickerMode` so a polling screen on an unselected
/// tab stops: an [IndexedStack] keeps every child mounted and building, and
/// [PollingScope] reads `TickerMode` to decide whether anyone is looking.
class DriverHomeShell extends StatefulWidget {
  const DriverHomeShell({super.key, required this.vehicleSeats});

  final int vehicleSeats;

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PostTripController>(
          create: (ctx) => PostTripController(
            api: ctx.read<DriverTripApi>(),
            maxSeats: widget.vehicleSeats,
          )..loadCorridors(),
        ),
        ChangeNotifierProvider<MyTripsController>(
          create: (ctx) => MyTripsController(api: ctx.read<DriverTripApi>()),
        ),
        ChangeNotifierProvider<PoolBoardController>(
          // Loaded once here rather than only when the board is opened: the
          // nav badge is what tells a driver pools exist at all, and a badge
          // that only appears after you have already found the thing it points
          // at is no use. The board's own PollingScope keeps it fresh from
          // there.
          create: (ctx) => PoolBoardController(
            api: ctx.read<PoolApi>(),
            vehicleSeats: widget.vehicleSeats,
          )..load(),
        ),
        ChangeNotifierProvider<EarningsController>(
          create: (ctx) => EarningsController(api: ctx.read<DriverTripApi>()),
        ),
      ],
      // A child of the providers, not a sibling: the nav badge reads the board
      // controller, and `build`'s own context sits ABOVE everything
      // MultiProvider creates.
      child: const _DriverHome(),
    );
  }
}

class _DriverHome extends StatefulWidget {
  const _DriverHome();

  @override
  State<_DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<_DriverHome> {
  int _index = 0;

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
                _Tab(
                  selected: _index == 0,
                  child: GetWorkScreen(
                    onWorkStarted: () => setState(() => _index = 1),
                  ),
                ),
                _Tab(selected: _index == 1, child: const MyTripsScreen()),
                _Tab(selected: _index == 2, child: const EarningsScreen()),
                _Tab(selected: _index == 3, child: const NotificationsScreen()),
                _Tab(
                  selected: _index == 4,
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
                FloatingPillNavItem(
                  icon: AppIcons.plusCircle,
                  label: 'العمل',
                  // The board's size, on the nav itself. A driver who has never
                  // opened the tab learns that pools exist — and that there are
                  // some RIGHT NOW — without being sent a nudge.
                  badgeCount: context.watch<PoolBoardController>().count,
                ),
                const FloatingPillNavItem(
                    icon: AppIcons.route, label: 'رحلاتي'),
                const FloatingPillNavItem(
                    icon: AppIcons.wallet, label: 'أرباحي'),
                FloatingPillNavItem(
                  icon: AppIcons.bell,
                  label: 'إشعارات',
                  badgeCount:
                      context.watch<NotificationsController>().unreadCount,
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
