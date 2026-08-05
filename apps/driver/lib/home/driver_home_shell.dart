import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../config/app_config.dart';
import '../earnings/earnings_controller.dart';
import '../earnings/earnings_screen.dart';
import '../trip/driver_trip_api.dart';
import '../trip/my_trips_controller.dart';
import '../trip/my_trips_screen.dart';
import '../trip/post_trip_controller.dart';
import '../trip/post_trip_screen.dart';

/// The APPROVED driver's home: a five-tab shell (انشر · رحلاتي · أرباحي ·
/// إشعارات · حسابي). Owns the post-trip, my-trips and earnings controllers;
/// the account tab is the shared Settings. Seat count is capped at
/// [vehicleSeats].
///
/// Five tabs is the pill's documented maximum and it needed the tighter inset
/// to keep every label on one line — see [FloatingPillNav].
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
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
        ChangeNotifierProvider<EarningsController>(
          create: (ctx) => EarningsController(api: ctx.read<DriverTripApi>()),
        ),
      ],
      child: Scaffold(
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
                    child: PostTripScreen(
                        onPosted: () => setState(() => _index = 1)),
                  ),
                  _Tab(selected: _index == 1, child: const MyTripsScreen()),
                  _Tab(selected: _index == 2, child: const EarningsScreen()),
                  _Tab(
                      selected: _index == 3,
                      child: const NotificationsScreen()),
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
                  const FloatingPillNavItem(
                      icon: AppIcons.plusCircle, label: 'انشر'),
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
                  const FloatingPillNavItem(
                      icon: AppIcons.user, label: 'حسابي'),
                ],
              ),
            ),
          ],
        ),
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
