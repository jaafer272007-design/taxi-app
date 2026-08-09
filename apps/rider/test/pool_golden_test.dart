import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/pool/price_raise_sheet.dart';
import 'package:rider/pool/seat_request_form_controller.dart';
import 'package:rider/pool/seat_request_models.dart';
import 'package:rider/pool/seat_request_screen.dart';
import 'package:rider/pool/seat_request_sent_screen.dart';
import 'package:shared/shared.dart';

import 'support/pool_fakes.dart';

/// Goldens for «اطلب مقعد» — Phase 2, the rider's half.
///
/// Three screens, both themes, RTL, Arabic, real Cairo. They exist to be
/// LOOKED AT, not merely to pass: everything this codebase has caught visually
/// — the tofu arrow, the fused `٠` dot, a colour caught mid-`lerp` — was found
/// by opening the PNG, never by the test going green.
///
/// The one that most needs looking at is the price-raise sheet. It is the only
/// place in the app where a price moves after a rider commits, so the shot is
/// the evidence that decline is as findable as accept and that nothing on it
/// manufactures urgency.
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

  group('اطلب مقعد — the form', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'seat_request_form_light',
          brightness: Brightness.light,
          child: _form());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'seat_request_form_dark',
          brightness: Brightness.dark,
          child: _form());
    });
  });

  // The form scrolled to the bottom. The price, the total, the one way the
  // price can move, and «هذا طلب وليس حجزاً» all live below the fold on a
  // 390×844 phone — and they are the whole point of the screen, so a reviewer
  // has to be able to see them without running the app.
  group('اطلب مقعد — السعر وما تحته', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'seat_request_form_price_light',
          brightness: Brightness.light,
          child: _form(),
          afterPump: _scrollToBottom);
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'seat_request_form_price_dark',
          brightness: Brightness.dark,
          child: _form(),
          afterPump: _scrollToBottom);
    });
  });

  group('أرسلنا طلبك', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'seat_request_sent_light',
          brightness: Brightness.light,
          child: _sent());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'seat_request_sent_dark',
          brightness: Brightness.dark,
          child: _sent());
    });
  });

  group('السائق يقترح سعراً أعلى', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'price_raise_sheet_light',
          brightness: Brightness.light,
          child: _raiseSheet());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'price_raise_sheet_dark',
          brightness: Brightness.dark,
          child: _raiseSheet());
    });
  });
}

/// Device location that always declines — the picker is never opened here.
class _NullLocation implements LocationService {
  const _NullLocation();

  @override
  Future<LocationResult> currentLocation() async =>
      const LocationResult(LocationStatus.denied);
}

/// A filled-in form: three seats (never two — the dual «مقعدان» carries no
/// digit, so a two-seat shot cannot show a fused `٠`), both points chosen.
Widget _form() {
  final c = SeatRequestFormController(
    api: FakeSeatRequestApi(),
    corridorId: 'c1',
    originCity: 'Najaf',
    destCity: 'Karbala',
    pricePerSeat: 6000,
    day: DateTime(2026, 8, 12),
  )
    ..setSeatCount(3)
    ..setWindow(const TimeOfDay(hour: 7, minute: 30),
        const TimeOfDay(hour: 10, minute: 30))
    ..setPickupPoint(const GeoPoint(
        lat: 31.99, lng: 44.31, label: 'حي السلام، قرب الجامع'))
    ..setDropoffPoint(const GeoPoint(
        lat: 32.61, lng: 44.02, label: 'قرب المستشفى التعليمي'));

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SeatRequestFormController>.value(value: c),
      Provider<LocationService>.value(value: const _NullLocation()),
      Provider<ReverseGeocoder>.value(value: const NullReverseGeocoder()),
    ],
    child: const SeatRequestScreen(),
  );
}

Widget _sent() => SeatRequestSentScreen(
      originCity: 'Najaf',
      destCity: 'Karbala',
      windowStart: DateTime(2026, 8, 12, 7, 30),
      windowEnd: DateTime(2026, 8, 12, 10, 30),
      seatCount: 3,
      pricePerSeat: 6000,
    );

/// The sheet hosted bare, over the page background.
///
/// [ColoredBox] because a modal sheet rendered without a route behind it would
/// snapshot on transparent black and stop saying anything about the light
/// theme. And [Material] because `showModalBottomSheet` supplies one in
/// production — without it every line of copy came back wearing Flutter's
/// yellow "no Material ancestor" underline, which is a fault in the harness,
/// not in the sheet, and made the first shot unreadable.
Widget _raiseSheet() => Builder(
      builder: (context) => ColoredBox(
        color: context.colors.background,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Material(
              color: Colors.transparent,
              child: PriceRaiseSheet(
                request: seatRequestFixture(
                  stage: SeatRequestStage.raisePending,
                  seatCount: 3,
                  raise: raiseFixture(
                      oldPricePerSeat: 6000, newPricePerSeat: 9000),
                ),
                onRespond: ({required bool accept}) async => null,
              ),
            ),
          ],
        ),
      ),
    );

/// Drag the form up so the price card and the CTA are in frame.
Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -900));
  // Past the 120ms cross-fade AND past the scroll settling: a golden taken
  // mid-fling catches a position nobody ever sees.
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
  Future<void> Function(WidgetTester)? afterPump,
}) async {
  // A real phone: logical 390×844, exactly as the other suites shoot.
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
      // RTL on the MaterialApp via `builder`, not around `home`: a modal route
      // is pushed ABOVE home, so a Directionality around home would not reach
      // it — and `TaxiApp` sets it here too.
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

  if (afterPump != null) await afterPump(tester);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
