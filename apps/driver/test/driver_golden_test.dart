import 'package:driver/driver/become_driver_screen.dart';
import 'package:driver/driver/documents_screen.dart';
import 'package:driver/driver/driver_controller.dart';
import 'package:driver/driver/driver_models.dart';
import 'package:driver/driver/pending_review_screen.dart';
import 'package:driver/driver/vehicle_form_screen.dart';
import 'package:driver/earnings/earnings_controller.dart';
import 'package:driver/earnings/earnings_screen.dart';
import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/my_trips_controller.dart';
import 'package:driver/trip/my_trips_screen.dart';
import 'package:driver/trip/post_trip_controller.dart';
import 'package:driver/trip/post_trip_screen.dart';
import 'package:driver/trip/rate_rider_sheet.dart';
import 'package:driver/trip/trip_detail_controller.dart';
import 'package:driver/trip/trip_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

/// Golden (visual snapshot) tests for the driver onboarding + post-trip screens,
/// BOTH light and dark, RTL, Arabic, real Cairo + Lucide fonts, at a 390×844
/// phone frame. CI generates the PNGs and mirrors them to docs/ui-screenshots/.
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

  _screen('become_driver', _becomeDriver);
  _screen('vehicle_form', _vehicleForm);
  _screen('documents', _documents);
  _screen('pending_review', _pending);
  _screen('post_trip', _postTrip);
  _screen('my_trips', _myTrips);
  _screen('trip_detail', _tripDetailOpen);
  _screen('trip_detail_enroute', _tripDetailEnRoute);
  _screen('trip_completed', _tripCompleted);
  _screen('earnings', _earnings);
  _screen('rate_rider', _rateRider);
}

void _screen(String name, Future<Widget> Function() build) {
  group(name, () {
    testWidgets('light', (t) async {
      await _golden(t, name: '${name}_light', brightness: Brightness.light, child: await build());
    });
    testWidgets('dark', (t) async {
      await _golden(t, name: '${name}_dark', brightness: Brightness.dark, child: await build());
    });
  });
}

Future<DriverController> _driver(DriverProfile? profile) async {
  final api = FakeDriverApi()..profile = profile;
  final c = DriverController(api: api, picker: FakeDocumentPicker());
  await c.load();
  return c;
}

Future<Widget> _becomeDriver() async {
  final c = await _driver(null);
  return ChangeNotifierProvider<DriverController>.value(
      value: c, child: const BecomeDriverScreen());
}

Future<Widget> _vehicleForm() async {
  final c = await _driver(profileFixture(status: DriverStatus.pending));
  return ChangeNotifierProvider<DriverController>.value(
      value: c, child: const VehicleFormScreen());
}

Future<Widget> _documents() async {
  final c = await _driver(profileFixture(
    status: DriverStatus.pending,
    vehicle: vehicleFixture(),
    documents: [
      docFixture(type: DocType.nationalId),
      docFixture(type: DocType.drivingLicense),
    ],
  ));
  return ChangeNotifierProvider<DriverController>.value(
      value: c, child: const DocumentsScreen());
}

Future<Widget> _pending() async {
  final c = await _driver(pendingWithAllDocs());
  return ChangeNotifierProvider<DriverController>.value(
      value: c, child: const PendingReviewScreen());
}

Future<Widget> _postTrip() async {
  final api = FakeDriverTripApi()..corridors = const [najafKarbala, karbalaNajaf];
  final c = PostTripController(api: api, maxSeats: 4);
  await c.loadCorridors();
  c.setSeatCount(2);
  return ChangeNotifierProvider<PostTripController>.value(
    value: c,
    child: PostTripScreen(onPosted: () {}),
  );
}

Future<Widget> _myTrips() async {
  final api = FakeDriverTripApi()
    ..corridors = const [najafKarbala, karbalaNajaf]
    ..myTripsResult = [
      tripFixture(
        id: 't1',
        corridorId: 'c1',
        hourUtc: 4,
        minute: 30,
        seatsAvailable: 2,
        status: TripStatus.open,
      ),
      tripFixture(
        id: 't2',
        corridorId: 'c2',
        hourUtc: 6,
        minute: 0,
        seatsAvailable: 0,
        status: TripStatus.locked,
      ),
    ];
  final c = MyTripsController(api: api);
  await c.load();
  return ChangeNotifierProvider<MyTripsController>.value(
      value: c, child: const MyTripsScreen());
}

Future<TripDetailController> _detail({
  required DriverTrip trip,
  required List<TripBooking> bookings,
  List<TripBooking>? settled,
}) async {
  final api = FakeDriverTripApi()
    ..tripBookingsResult = bookings
    ..settledBookingsResult = settled;
  final c = TripDetailController(api: api, trip: trip, corridor: najafKarbala);
  await c.load();
  return c;
}

Widget _hostDetail(TripDetailController c) =>
    ChangeNotifierProvider<TripDetailController>.value(
        value: c, child: const TripDetailScreen());

/// OPEN trip with two confirmed bookings → start + (soft) cancel actions.
Future<Widget> _tripDetailOpen() async {
  final c = await _detail(
    trip: tripFixture(status: TripStatus.open, seatsTotal: 4, seatsAvailable: 2),
    bookings: [
      bookingFixture(
          id: 'b1', riderId: 'r1', riderName: 'علي حسن', seatCount: 2, fare: 12000),
      bookingFixture(
          id: 'b2',
          riderId: 'r2',
          riderName: 'حسن كريم',
          pickupLabel: 'دوار الثورة',
          dropoffLabel: 'الحرم'),
    ],
  );
  return _hostDetail(c);
}

/// EN_ROUTE trip → per-rider onboard / no-show; one already onboard, one no-show.
Future<Widget> _tripDetailEnRoute() async {
  final c = await _detail(
    trip: tripFixture(
        status: TripStatus.enRoute, seatsTotal: 4, seatsAvailable: 0),
    bookings: [
      bookingFixture(
          id: 'b1', riderId: 'r1', riderName: 'علي حسن', seatCount: 2, fare: 12000),
      bookingFixture(
          id: 'b2',
          riderId: 'r2',
          riderName: 'حسن كريم',
          status: BookingStatus.onboard),
      bookingFixture(
          id: 'b3',
          riderId: 'r3',
          riderName: 'مصطفى جواد',
          status: BookingStatus.noShow),
    ],
  );
  return _hostDetail(c);
}

/// Settled trip → completion summary + rate rows (one rider already rated).
Future<Widget> _tripCompleted() async {
  final c = await _detail(
    trip: tripFixture(
        status: TripStatus.enRoute, seatsTotal: 4, seatsAvailable: 0),
    bookings: [
      bookingFixture(id: 'b1', riderId: 'r1', seatCount: 2, fare: 12000),
      bookingFixture(id: 'b2', riderId: 'r2', fare: 6000),
      bookingFixture(id: 'b3', riderId: 'r3', status: BookingStatus.confirmed),
    ],
    settled: [
      bookingFixture(
          id: 'b1',
          riderId: 'r1',
          riderName: 'علي حسن',
          seatCount: 2,
          fare: 12000,
          status: BookingStatus.completed),
      bookingFixture(
          id: 'b2',
          riderId: 'r2',
          riderName: 'حسن كريم',
          fare: 6000,
          status: BookingStatus.completed),
      bookingFixture(
          id: 'b3',
          riderId: 'r3',
          riderName: 'مصطفى جواد',
          status: BookingStatus.noShow),
    ],
  );
  await c.complete(); // → settled, summary built, bookings become COMPLETED
  await c.rateRider(riderId: 'r1', score: 5); // first rider already rated
  return _hostDetail(c);
}

Future<Widget> _earnings() async {
  final api = FakeDriverTripApi()
    ..earningsByRange = {
      'today': const DriverEarnings(total: 18000, records: []),
      'all': DriverEarnings(total: 96000, records: [
        earningsRecordFixture(id: 'e1', amount: 12000, hourUtc: 6, minute: 15),
        earningsRecordFixture(id: 'e2', amount: 6000, hourUtc: 4, minute: 30),
        earningsRecordFixture(id: 'e3', amount: 18000, hourUtc: 2, minute: 0),
      ]),
    };
  final c = EarningsController(api: api);
  await c.load();
  return ChangeNotifierProvider<EarningsController>.value(
      value: c, child: const EarningsScreen());
}

/// The rate-a-rider sheet body, hosted on a surface like the real modal.
Future<Widget> _rateRider() async {
  return Builder(
    builder: (context) => ColoredBox(
      color: context.colors.background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Material(
            color: context.colors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(context.radii.lg)),
            clipBehavior: Clip.antiAlias,
            child: RateRiderSheet(
              riderName: 'علي حسن',
              onSubmit: (_, __) async => null,
            ),
          ),
        ],
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
