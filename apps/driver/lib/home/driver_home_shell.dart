import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../trip/driver_trip_api.dart';
import '../trip/my_trips_controller.dart';
import '../trip/my_trips_screen.dart';
import '../trip/post_trip_controller.dart';
import '../trip/post_trip_screen.dart';

/// The APPROVED driver's home: a two-tab shell (انشر رحلة · رحلاتي). Owns the
/// post-trip + my-trips controllers; seat count is capped at [vehicleSeats].
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
      ],
      child: Scaffold(
        backgroundColor: colors.background,
        body: IndexedStack(
          index: _index,
          children: [
            PostTripScreen(onPosted: () => setState(() => _index = 1)),
            const MyTripsScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: colors.surface,
          indicatorColor: colors.primary.withValues(alpha: 0.14),
          destinations: const [
            NavigationDestination(icon: Icon(AppIcons.plusCircle), label: 'انشر رحلة'),
            NavigationDestination(icon: Icon(AppIcons.route), label: 'رحلاتي'),
          ],
        ),
      ),
    );
  }
}
