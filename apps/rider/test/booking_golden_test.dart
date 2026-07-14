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
import 'package:rider/core/api_exception.dart';
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
          height: 1240,
          child: _bookingForm());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'booking_dark',
          brightness: Brightness.dark,
          height: 1240,
          child: _bookingForm());
    });
  });

  group('booking confirmation', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'booking_confirmation_light',
          brightness: Brightness.light,
          height: 900,
          child: _confirmation());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'booking_confirmation_dark',
          brightness: Brightness.dark,
          height: 900,
          child: _confirmation());
    });
  });

  group('booking seat-taken error', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'booking_error_light',
          brightness: Brightness.light,
          height: 1440,
          child: await _bookingErrorForm());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'booking_error_dark',
          brightness: Brightness.dark,
          height: 1440,
          child: await _bookingErrorForm());
    });
  });

  group('my bookings', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'my_bookings_light',
          brightness: Brightness.light,
          height: 1040,
          child: await _myBookings());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'my_bookings_dark',
          brightness: Brightness.dark,
          height: 1040,
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
    ..setPickupLabel('حي السلام، قرب الجامع')
    ..setDropoffLabel('قرب المستشفى التعليمي')
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
    ..setPickupLabel('حي السلام')
    ..setDropoffLabel('قرب المستشفى');
  await c.submit(); // → seatGone error state
  return ChangeNotifierProvider<BookingController>.value(
    value: c,
    child: const BookingScreen(),
  );
}

Widget _confirmation() => BookingConfirmationScreen(
      seatCount: 2,
      fare: 12000,
      departureTime: DateTime.utc(2026, 7, 20, 4, 30),
      originCity: 'Najaf',
      destCity: 'Karbala',
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
      ),
    ];
  final c = MyBookingsController(api: api);
  await c.load(); // hasLoaded → the screen won't re-fetch
  return ChangeNotifierProvider<MyBookingsController>.value(
    value: c,
    child: const MyBookingsScreen(),
  );
}

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
  required double height,
}) async {
  const width = 400.0;
  const dpr = 2.0;
  tester.view.physicalSize = Size(width * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme =
      brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );

  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
