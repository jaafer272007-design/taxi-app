import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_confirmation_screen.dart';
import 'package:rider/booking/booking_controller.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/booking/booking_screen.dart';
import 'package:rider/booking/my_bookings_controller.dart';
import 'package:rider/booking/my_bookings_screen.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';
import 'support/trip_fakes.dart';

/// Golden (visual snapshot) tests for the booking flow — the reserve-a-seat
/// form, the confirmation screen, the seat-taken error state, and "حجوزاتي" —
/// in BOTH light and dark, RTL, Arabic, with real Cairo + Lucide fonts.
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

  group('booking form', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'booking_light',
          brightness: Brightness.light,
          child: _bookingForm());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'booking_dark',
          brightness: Brightness.dark,
          child: _bookingForm());
    });
  });

  group('booking confirmation', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'booking_confirmation_light',
          brightness: Brightness.light,
          child: _confirmation());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'booking_confirmation_dark',
          brightness: Brightness.dark,
          child: _confirmation());
    });
  });

  group('booking seat-taken error', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'booking_error_light',
          brightness: Brightness.light,
          child: await _bookingErrorForm());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'booking_error_dark',
          brightness: Brightness.dark,
          child: await _bookingErrorForm());
    });
  });

  group('my bookings — سابقة, where the rate action lives', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'my_bookings_past_light',
          brightness: Brightness.light,
          child: await _myBookings(),
          afterPump: _openPastTab);
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'my_bookings_past_dark',
          brightness: Brightness.dark,
          child: await _myBookings(),
          afterPump: _openPastTab);
    });
  });

  group('rate the driver', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'rate_driver_sheet_light',
          brightness: Brightness.light,
          child: _rateDriverSheet());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'rate_driver_sheet_dark',
          brightness: Brightness.dark,
          child: _rateDriverSheet());
    });
  });

  group('my bookings', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'my_bookings_light',
          brightness: Brightness.light,
          child: await _myBookings());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'my_bookings_dark',
          brightness: Brightness.dark,
          child: await _myBookings());
    });
  });
}

Widget _bookingForm() {
  final c = BookingController(
    api: FakeBookingApi(),
    trip: tripFixture(seatsAvailable: 3, price: 6000, rating: 4.5),
    originCity: 'Najaf',
    destCity: 'Karbala',
  )
    ..setPickupPoint(const GeoPoint(
        lat: 31.99, lng: 44.31, label: 'حي السلام، قرب الجامع'))
    ..setDropoffPoint(const GeoPoint(
        lat: 32.61, lng: 44.02, label: 'قرب المستشفى التعليمي'))
    ..setSeatCount(2);
  return ChangeNotifierProvider<BookingController>.value(
    value: c,
    child: const BookingScreen(),
  );
}

Future<Widget> _bookingErrorForm() async {
  final api = FakeBookingApi()
    ..createError = const ApiException('لم يعد المقعد متاحاً.', statusCode: 409);
  final c = BookingController(
    api: api,
    trip: tripFixture(seatsAvailable: 1, price: 6000, rating: 5),
    originCity: 'Najaf',
    destCity: 'Karbala',
  )
    ..setPickupPoint(const GeoPoint(lat: 31.99, lng: 44.31, label: 'حي السلام'))
    ..setDropoffPoint(
        const GeoPoint(lat: 32.61, lng: 44.02, label: 'قرب المستشفى'));
  await c.submit(); // → seatGone error state
  return ChangeNotifierProvider<BookingController>.value(
    value: c,
    child: const BookingScreen(),
  );
}

/// A [LinkLauncher] that goes nowhere — the goldens render the buttons, they
/// never press them.
class _InertLauncher implements LinkLauncher {
  const _InertLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}

/// The confirmation as it looks in practice: the rider's own two points, and
/// the driver's number, which the booking has just entitled them to.
Widget _confirmation() => BookingConfirmationScreen(
      seatCount: 2,
      fare: 12000,
      departureTime: DateTime.utc(2026, 7, 20, 4, 30),
      originCity: 'Najaf',
      destCity: 'Karbala',
      pickup: const LocationPoint(
          lat: 31.999, lng: 44.3148, label: 'قرية الغدير السكنية'),
      dropoff: const LocationPoint(
          lat: 32.616, lng: 44.0242, label: 'طريق الحر، حي الزيتون'),
      driverContact: contactFixture(name: 'أبو علي', phone: '+9647701234567'),
    );

Future<Widget> _myBookings() async {
  final api = FakeBookingApi()
    ..listMineResult = [
      mineFixture(
        id: 'b1',
        seatCount: 2,
        fare: 12000,
        status: BookingStatus.confirmed,
        upcoming: true,
        hourUtc: 4,
        minute: 30,
      ),
      mineFixture(
        id: 'b2',
        seatCount: 1,
        fare: 6000,
        status: BookingStatus.completed,
        upcoming: false,
        hourUtc: 6,
        minute: 0,
        // Completed and unrated → the rate prompt rides at the top of the
        // screen and the card below carries «قيّم السائق».
        ratable: true,
        driverName: 'أبو علي',
      ),
    ]
    // The fake returns this for any trip, but only the UPCOMING booking is ever
    // asked about — so the past card below has no contact row, which is the
    // rule made visible.
    ..driverContactResult =
        contactFixture(name: 'أبو علي', phone: '+9647701234567');
  final c = MyBookingsController(api: api);
  await c.load(); // hasLoaded → the screen won't re-fetch
  return ChangeNotifierProvider<MyBookingsController>.value(
    value: c,
    child: const MyBookingsScreen(),
  );
}

/// Switch حجوزاتي to «سابقة» before the snapshot — the rate action lives on a
/// completed ride, and the screen opens on «قادمة».
Future<void> _openPastTab(WidgetTester tester) async {
  // The pill carries its count («سابقة ١»), and the empty-state line ends with
  // the same word — anchor so exactly one thing matches.
  await tester.tap(find.textContaining(RegExp('^سابقة')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
}

/// The rider's half of the shared [RateSheet] — same body the driver uses to
/// rate riders, different words.
Widget _rateDriverSheet() => Directionality(
      textDirection: TextDirection.rtl,
      child: Builder(
        builder: (context) => Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Material(
              color: context.colors.surface,
              borderRadius: context.radii.sheetTop,
              clipBehavior: Clip.antiAlias,
              child: const RateSheet(
                title: 'قيّم السائق',
                name: 'أبو علي',
                commentHint: 'كيف كانت الرحلة مع هذا السائق؟',
                onSubmit: _noopSubmit,
              ),
            ),
          ],
        ),
      ),
    );

Future<String?> _noopSubmit(int score, String? comment) async => null;

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
  Future<void> Function(WidgetTester)? afterPump,
}) async {
  // Render at a real phone size (logical 390×844) so screens render at true
  // proportions with the bottom button pinned at its natural size/position.
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
    Provider<LinkLauncher>.value(
      // Contact rows read the launcher from the tree at build time; the goldens
      // render the buttons without ever pressing them.
      value: const _InertLauncher(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    ),
  );

  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));

  if (afterPump != null) await afterPump(tester);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
