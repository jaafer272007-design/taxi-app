import 'package:driver/driver/become_driver_screen.dart';
import 'package:driver/driver/documents_screen.dart';
import 'package:driver/driver/driver_controller.dart';
import 'package:driver/driver/driver_models.dart';
import 'package:driver/driver/pending_review_screen.dart';
import 'package:driver/driver/vehicle_form_screen.dart';
import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/my_trips_controller.dart';
import 'package:driver/trip/my_trips_screen.dart';
import 'package:driver/trip/post_trip_controller.dart';
import 'package:driver/trip/post_trip_screen.dart';
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
