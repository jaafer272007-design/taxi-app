import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:rider/auth/name_screen.dart';
import 'package:rider/trip/results_screen.dart';
import 'package:rider/trip/search_screen.dart';
import 'package:rider/trip/trip_details_screen.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:rider/trip/trip_search_controller.dart';
import 'package:shared/shared.dart';

import 'support/fakes.dart';
import 'support/trip_fakes.dart';

/// Golden (visual snapshot) tests for the trip search/results/details + onboarding
/// (name + gender) screens in BOTH light and dark, RTL, Arabic, with the real
/// Cairo + Lucide fonts loaded. CI generates the PNGs and mirrors them to
/// docs/ui-screenshots/.
void main() {
  setUpAll(() async {
    // Lucide icon font (flutter_test doesn't auto-load dependency fonts).
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(
              rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf')))
        .load();
    // Cairo from the bundled shared assets (no network).
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.light();
    AppTheme.dark();
    await GoogleFonts.pendingFonts();
  });

  group('rider_profile', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'rider_profile_light',
          brightness: Brightness.light,
          auth: _freshAuth(),
          child: const NameScreen());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'rider_profile_dark',
          brightness: Brightness.dark,
          auth: _freshAuth(),
          child: const NameScreen());
    });
  });

  group('search', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'search_light',
          brightness: Brightness.light,
          controller: await _searchController(),
          child: const SearchScreen());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'search_dark',
          brightness: Brightness.dark,
          controller: await _searchController(),
          child: const SearchScreen());
    });
  });

  group('city_picker', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'city_picker_light',
          brightness: Brightness.light,
          child: _cityPickerSheet());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'city_picker_dark',
          brightness: Brightness.dark,
          child: _cityPickerSheet());
    });
  });

  group('results', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'results_light',
          brightness: Brightness.light,
          controller: await _resultsController(),
          child: const ResultsScreen());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'results_dark',
          brightness: Brightness.dark,
          controller: await _resultsController(),
          child: const ResultsScreen());
    });
  });

  group('empty', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'empty_light',
          brightness: Brightness.light,
          controller: await _emptyController(),
          child: const ResultsScreen());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'empty_dark',
          brightness: Brightness.dark,
          controller: await _emptyController(),
          child: const ResultsScreen());
    });
  });

  group('empty_filtered', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'empty_filtered_light',
          brightness: Brightness.light,
          controller: await _emptyFilteredController(),
          child: const ResultsScreen());
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'empty_filtered_dark',
          brightness: Brightness.dark,
          controller: await _emptyFilteredController(),
          child: const ResultsScreen());
    });
  });

  group('details', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'details_light',
          brightness: Brightness.light,
          auth: await _riderAuth(Gender.male),
          child: TripDetailsScreen(trip: tripFixture()));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'details_dark',
          brightness: Brightness.dark,
          auth: await _riderAuth(Gender.male),
          child: TripDetailsScreen(trip: tripFixture()));
    });
  });

  group('details_women_blocked', () {
    testWidgets('light', (t) async {
      await _golden(t,
          name: 'details_women_blocked_light',
          brightness: Brightness.light,
          auth: await _riderAuth(Gender.male),
          child: TripDetailsScreen(
              trip: tripFixture(
                  tripType: TripType.womenFamily,
                  driverGender: Gender.female)));
    });
    testWidgets('dark', (t) async {
      await _golden(t,
          name: 'details_women_blocked_dark',
          brightness: Brightness.dark,
          auth: await _riderAuth(Gender.male),
          child: TripDetailsScreen(
              trip: tripFixture(
                  tripType: TripType.womenFamily,
                  driverGender: Gender.female)));
    });
  });
}

/// The canonical-city picker rendered like the modal bottom sheet it opens as
/// (bottom-aligned, rounded top), so the full 18-city dropdown is visible.
Widget _cityPickerSheet() => Builder(
      builder: (context) => ColoredBox(
        color: context.colors.background,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 640,
            child: Material(
              color: context.colors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(context.radii.lg)),
              clipBehavior: Clip.antiAlias,
              child: AppCityPickerSheet(selected: 'Najaf', onSelect: (_) {}),
            ),
          ),
        ),
      ),
    );

AuthController _freshAuth() =>
    AuthController(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());

Future<AuthController> _riderAuth(Gender gender) async {
  final api = FakeAuthApi()..meResult = fakeUser(name: 'راكب', gender: gender);
  final c = AuthController(api: api, tokenStore: InMemoryTokenStore('jwt'));
  await c.bootstrap();
  return c;
}

Future<TripSearchController> _searchController() async {
  final api = FakeTripApi()..corridors = const [najafKarbala, karbalaNajaf];
  final c = TripSearchController(api: api);
  await c.ensureCorridorsLoaded();
  return c;
}

Future<TripSearchController> _resultsController() async {
  final api = FakeTripApi()
    ..corridors = const [najafKarbala]
    ..searchResults = [
      tripFixture(
          id: 't1',
          hourUtc: 4,
          seatsAvailable: 3,
          driverName: 'علي حسن',
          rating: 4.5,
          driverGender: Gender.male),
      tripFixture(
        id: 't2',
        hourUtc: 5,
        minute: 15,
        seatsAvailable: 1,
        driverName: 'زينب علي',
        rating: 5,
        price: 6500,
        driverGender: Gender.female,
        tripType: TripType.womenFamily,
        vehicle: const TripVehicle(make: 'Kia', model: 'Rio', color: 'أسود', seats: 4),
      ),
      tripFixture(
          id: 't3',
          hourUtc: 7,
          seatsAvailable: 2,
          driverName: 'حسين عبد الله',
          rating: 4,
          price: 5000),
    ];
  final c = TripSearchController(api: api);
  await c.ensureCorridorsLoaded();
  await c.search();
  return c;
}

Future<TripSearchController> _emptyController() async {
  final api = FakeTripApi()
    ..corridors = const [najafKarbala]
    ..searchResults = const [];
  final c = TripSearchController(api: api);
  await c.ensureCorridorsLoaded();
  await c.search();
  return c;
}

Future<TripSearchController> _emptyFilteredController() async {
  final api = FakeTripApi()
    ..corridors = const [najafKarbala]
    ..searchResults = const []; // female drivers are rare → filtered-empty
  final c = TripSearchController(api: api);
  await c.ensureCorridorsLoaded();
  c.setDriverGender(Gender.female);
  await c.search();
  return c;
}

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget child,
  TripSearchController? controller,
  AuthController? auth,
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

  Widget body = child;
  if (auth != null) {
    body = ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: body,
    );
  }
  if (controller != null) {
    body = ChangeNotifierProvider<TripSearchController>.value(
      value: controller,
      child: body,
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Directionality(textDirection: TextDirection.rtl, child: body),
    ),
  );

  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
