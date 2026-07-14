import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../booking/booking_api.dart';
import '../booking/my_bookings_controller.dart';
import '../booking/my_bookings_screen.dart';
import '../trip/search_screen.dart';

/// The authenticated home: a two-tab shell (ابحث · حجوزاتي). Each tab keeps its
/// own state across switches (an [IndexedStack]); the bookings tab owns its
/// [MyBookingsController].
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
      body: IndexedStack(
        index: _index,
        children: [
          const SearchScreen(),
          ChangeNotifierProvider<MyBookingsController>(
            create: (ctx) => MyBookingsController(api: ctx.read<BookingApi>()),
            child: const MyBookingsScreen(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: colors.surface,
        indicatorColor: colors.primary.withValues(alpha: 0.14),
        destinations: const [
          NavigationDestination(icon: Icon(AppIcons.search), label: 'ابحث'),
          NavigationDestination(icon: Icon(AppIcons.seat), label: 'حجوزاتي'),
        ],
      ),
    );
  }
}
