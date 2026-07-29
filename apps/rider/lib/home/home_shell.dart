import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../booking/booking_api.dart';
import '../booking/my_bookings_controller.dart';
import '../booking/my_bookings_screen.dart';
import '../config/app_config.dart';
import '../trip/search_screen.dart';

/// The authenticated home: a three-tab shell (ابحث · حجوزاتي · حسابي). Each tab
/// keeps its own state across switches (an [IndexedStack]); the bookings tab
/// owns its [MyBookingsController]; the account tab is the shared Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
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
                const SearchScreen(),
                ChangeNotifierProvider<MyBookingsController>(
                  create: (ctx) =>
                      MyBookingsController(api: ctx.read<BookingApi>()),
                  child: const MyBookingsScreen(),
                ),
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
                FloatingPillNavItem(icon: AppIcons.search, label: 'ابحث'),
                FloatingPillNavItem(icon: AppIcons.seat, label: 'حجوزاتي'),
                FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
