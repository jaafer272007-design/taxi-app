import 'package:driver/pool/pool_board_controller.dart';
import 'package:driver/pool/pool_board_screen.dart';
import 'package:driver/pool/pool_models.dart';
import 'package:driver/pool/raise_controller.dart';
import 'package:driver/pool/raise_panel.dart';
import 'package:driver/pool/raise_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/pool_fakes.dart';

/// Goldens for the driver's half of Phase 2 — the board and the raise flow.
///
/// They exist to be LOOKED AT. Every visual bug this codebase has caught was
/// found by opening the PNG, never by the test going green: the tofu arrow, the
/// fused `٠` dot, a colour caught mid-`lerp`, a strikethrough that made the
/// wrong number the harder one to read.
///
/// The two that most need looking at here are the **board card** — four blocks
/// that have to answer "is this worth driving?" in one glance — and the
/// **propose sheet**, where the driver is being shown a trade that is not
/// obviously good for them.
void main() {
  setUpAll(() async {
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(
              rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf')))
        .load();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.light();
    AppTheme.dark();
    await GoogleFonts.pendingFonts();
  });

  group('لوحة التجمّعات', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'pool_board_light',
          brightness: Brightness.light,
          child: await _board());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'pool_board_dark',
          brightness: Brightness.dark,
          child: await _board());
    });
  });

  group('لوحة التجمّعات — فارغة', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'pool_board_empty_light',
          brightness: Brightness.light,
          child: await _board(pools: const []));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'pool_board_empty_dark',
          brightness: Brightness.dark,
          child: await _board(pools: const []));
    });
  });

  group('اقترح سعراً أعلى', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'raise_sheet_light',
          brightness: Brightness.light,
          child: _raiseSheet());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'raise_sheet_dark',
          brightness: Brightness.dark,
          child: _raiseSheet());
    });
  });

  // The case where raising is a BAD trade — the sheet has to say so as loudly
  // as it says anything else, which is exactly the thing to check by eye.
  group('اقترح سعراً أعلى — الحد الأدنى بالضبط', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'raise_sheet_risky_light',
          brightness: Brightness.light,
          child: _raiseSheet(seatsTaken: 2));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'raise_sheet_risky_dark',
          brightness: Brightness.dark,
          child: _raiseSheet(seatsTaken: 2));
    });
  });

  group('بانتظار ردّ الركّاب', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'raise_waiting_light',
          brightness: Brightness.light,
          child: await _panel(driverPoolFixture(raise: raiseFixture())));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'raise_waiting_dark',
          brightness: Brightness.dark,
          child: await _panel(driverPoolFixture(raise: raiseFixture())));
    });
  });
}

Future<Widget> _board({List<BoardPool>? pools}) async {
  final api = FakePoolApi()
    ..boardResult = pools ??
        [
          boardPoolFixture(),
          boardPoolFixture(
            id: 'pool_2',
            totalSeats: 4,
            riderCount: 3,
            windowStart: DateTime(2026, 8, 12, 14, 0),
            stops: const [
              PoolStop(
                seatCount: 2,
                pickup:
                    LocationPoint(lat: 32.0, lng: 44.30, label: 'حي الأنصار'),
                dropoff:
                    LocationPoint(lat: 32.6, lng: 44.0, label: 'شارع العلقمي'),
              ),
              PoolStop(
                seatCount: 1,
                pickup: LocationPoint(lat: 32.08, lng: 44.40, label: 'المشراق'),
                dropoff: LocationPoint(lat: 32.61, lng: 44.02, label: 'الحر'),
              ),
              PoolStop(
                seatCount: 1,
                pickup: LocationPoint(lat: 32.02, lng: 44.33, label: 'الجديدة'),
                dropoff:
                    LocationPoint(lat: 32.62, lng: 44.03, label: 'باب السلالمة'),
              ),
            ],
          ),
        ];
  final c = PoolBoardController(api: api, vehicleSeats: 4);
  await c.load(); // hasLoaded → the screen won't re-fetch
  return ChangeNotifierProvider<PoolBoardController>.value(
    value: c,
    child: PoolBoardScreen(onClaimed: (_) {}),
  );
}

/// The propose sheet, hosted over the page background.
///
/// [ColoredBox] because a modal sheet with no route behind it would snapshot on
/// transparent black and say nothing about the light theme; [Material] because
/// `showModalBottomSheet` provides one in production, and without it every line
/// comes back wearing Flutter's yellow "no Material ancestor" underline.
Widget _raiseSheet({int seatsTaken = 3}) => Builder(
      builder: (context) => ColoredBox(
        color: context.colors.background,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Material(
              color: Colors.transparent,
              child: RaiseSheet(
                pool: driverPoolFixture(
                  seatsTaken: seatsTaken,
                  pricePerSeat: 6000,
                  maxPricePerSeat: 12000,
                ),
                onPropose: (_) async => null,
              ),
            ),
          ],
        ),
      ),
    );

Future<Widget> _panel(DriverPool pool) async {
  final api = FakePoolApi()..forTripResult = pool;
  final c = RaiseController(api: api, tripId: pool.tripId);
  await c.load();
  return ChangeNotifierProvider<RaiseController>.value(
    value: c,
    // Material because the real screen is inside a Scaffold — without one every
    // line came back wearing Flutter's yellow "no Material ancestor" underline,
    // which is a fault in the harness, not in the panel, and made the first
    // shot unreadable.
    child: Builder(
      builder: (context) => Material(
        color: context.colors.background,
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: RaisePanel(),
        ),
      ),
    ),
  );
}

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
}) async {
  // A real phone: logical 390×844, the same frame every other suite shoots.
  const width = 390.0;
  const height = 844.0;
  const dpr = 2.0;
  tester.view.physicalSize = const Size(width * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme =
      brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      // RTL on the MaterialApp via `builder`, as `TaxiApp` does — a modal route
      // is pushed ABOVE `home`, so a Directionality around home would not reach
      // it.
      builder: (context, widget) => Directionality(
        textDirection: TextDirection.rtl,
        child: widget!,
      ),
      home: child,
    ),
  );

  // Past the 120ms AppCard/AppButton cross-fade, twice over: a snapshot taken
  // mid-`lerp` ships a colour nobody ever sees.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
