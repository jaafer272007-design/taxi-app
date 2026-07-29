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

/// The APPROVED driver's home: a four-tab shell (انشر رحلة · رحلاتي · أرباحي ·
/// حسابي). Owns the post-trip, my-trips and earnings controllers; the account
/// tab is the shared Settings. Seat count is capped at [vehicleSeats].
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
                  PostTripScreen(onPosted: () => setState(() => _index = 1)),
                  const MyTripsScreen(),
                  const EarningsScreen(),
                  SettingsScreen(
                    appVersion: AppConfig.appVersion,
                    onLogout: () => context.read<AuthController>().logout(),
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
                items: const [
                  FloatingPillNavItem(
                      icon: AppIcons.plusCircle, label: 'انشر'),
                  FloatingPillNavItem(icon: AppIcons.route, label: 'رحلاتي'),
                  FloatingPillNavItem(icon: AppIcons.wallet, label: 'أرباحي'),
                  FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
