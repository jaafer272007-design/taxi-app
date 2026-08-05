import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// SingleChildWidget (the element type MultiProvider takes) — imported from its
// own entrypoint rather than relying on provider.dart re-exporting it.
import 'package:provider/single_child_widget.dart';
import 'package:rider/booking/booking_api.dart';
import 'package:rider/booking/booking_confirmation_screen.dart';
import 'package:rider/booking/booking_controller.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/booking/booking_screen.dart';
import 'package:rider/booking/my_bookings_controller.dart';
import 'package:rider/booking/my_bookings_screen.dart';
import 'package:rider/trip/results_screen.dart';
import 'package:rider/trip/trip_details_screen.dart';
import 'package:rider/trip/trip_search_controller.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';
import 'support/fakes.dart';
import 'support/trip_fakes.dart';

/// The rider's side of "who can I reach, and where exactly am I standing".
///
/// The locked rule: **real numbers, only after a booking exists.** A rider must
/// never be able to harvest every driver's mobile by scrolling search results,
/// so the pre-booking screens are asserted to carry no number at all — and that
/// assertion is the point of this file as much as the positive cases are.
class _FakeLauncher implements LinkLauncher {
  final List<Uri> opened = [];

  Uri? get last => opened.isEmpty ? null : opened.last;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

/// Any Iraqi mobile, in any of the forms a screen could render one.
final _phoneShaped = RegExp(r'\+?9647\d|07[5789]\d|\+964\s*7');

void main() {
  late _FakeLauncher launcher;

  setUp(() => launcher = _FakeLauncher());

  Widget host(Widget child, {List<SingleChildWidget> extra = const []}) =>
      MultiProvider(
        providers: [
          Provider<LinkLauncher>.value(value: launcher),
          ...extra,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      );

  /// Every string the screen actually rendered.
  List<String> renderedText(WidgetTester t) => t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data)
      .whereType<String>()
      .toList();


  /// Close a pushed map route inside the test body.
  ///
  /// NOT in a tearDown: FlutterMap owns tile-eviction timers, and flutter_test
  /// checks `!timersPending` BEFORE tearDown gets a turn — the same ordering
  /// that bit the onboarding lift. Disposing the route here cancels them.
  Future<void> closeMap(WidgetTester t) async {
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  /// The tap target of the point row carrying [label].
  ///
  /// Invoked rather than hit-tested: these rows sit below the fold of the
  /// 800×600 test surface, which is why every interaction test in this package
  /// calls the callback directly.
  Finder inkFor(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );

  // ── No number before a booking exists ────────────────────────────────────

  group('nothing pre-booking carries a phone number', () {
    testWidgets('search results do not', (t) async {
      // The harvesting case the rule exists to prevent.
      final c = TripSearchController(
        api: FakeTripApi()
          ..corridors = const [najafKarbala]
          ..searchResults = [
            tripFixture(id: 't1', driverName: 'أبو علي'),
            tripFixture(id: 't2', driverName: 'أبو حسن'),
          ],
      );
      await c.ensureCorridorsLoaded();
      await c.search();

      await t.pumpWidget(host(
        const ResultsScreen(),
        extra: [ChangeNotifierProvider<TripSearchController>.value(value: c)],
      ));
      await t.pump();

      expect(renderedText(t).where(_phoneShaped.hasMatch), isEmpty);
    });

    testWidgets('the trip details screen does not', (t) async {
      // Reached from search — the rider has not booked this trip, so there is
      // nothing to show and no code path that could show it.
      final auth = AuthController(
        api: FakeAuthApi(),
        tokenStore: InMemoryTokenStore(),
      );
      await t.pumpWidget(host(
        TripDetailsScreen(trip: tripFixture(driverName: 'أبو علي')),
        extra: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<BookingApi>.value(value: FakeBookingApi()),
        ],
      ));
      await t.pump();

      expect(renderedText(t).where(_phoneShaped.hasMatch), isEmpty);
    });

    testWidgets('the booking form does not', (t) async {
      final c = BookingController(
        api: FakeBookingApi(),
        trip: tripFixture(driverName: 'أبو علي'),
        originCity: 'Najaf',
        destCity: 'Karbala',
      )
        ..setPickupPoint(const GeoPoint(lat: 31.99, lng: 44.31, label: 'حي السلام'))
        ..setDropoffPoint(
            const GeoPoint(lat: 32.61, lng: 44.02, label: 'قرب المستشفى'));

      await t.pumpWidget(host(
        const BookingScreen(),
        extra: [ChangeNotifierProvider<BookingController>.value(value: c)],
      ));
      await t.pump();

      expect(renderedText(t).where(_phoneShaped.hasMatch), isEmpty);
    });
  });

  // ── The number, once the booking is real ─────────────────────────────────

  group('BookingController resolves the driver only AFTER booking', () {
    test('does not ask before submit', () async {
      final api = FakeBookingApi()..driverContactResult = contactFixture();
      final c = BookingController(api: api, trip: tripFixture())
        ..setPickupPoint(const GeoPoint(lat: 31.99, lng: 44.31, label: 'أ'))
        ..setDropoffPoint(const GeoPoint(lat: 32.61, lng: 44.02, label: 'ب'));

      expect(api.driverContactCalls, isEmpty);
      expect(c.driverContact, isNull);
    });

    test('asks once the seat is reserved', () async {
      final api = FakeBookingApi()
        ..driverContactResult = contactFixture(phone: '+9647701234567');
      final c = BookingController(api: api, trip: tripFixture(id: 't7'))
        ..setPickupPoint(const GeoPoint(lat: 31.99, lng: 44.31, label: 'أ'))
        ..setDropoffPoint(const GeoPoint(lat: 32.61, lng: 44.02, label: 'ب'));

      expect(await c.submit(), isTrue);

      expect(api.driverContactCalls, ['t7']);
      expect(c.driverContact!.phone, '+9647701234567');
    });

    test('never asks when the booking failed', () async {
      final api = FakeBookingApi()
        ..createError = const ApiException('لم يعد المقعد متاحاً.', statusCode: 409)
        ..driverContactResult = contactFixture();
      final c = BookingController(api: api, trip: tripFixture())
        ..setPickupPoint(const GeoPoint(lat: 31.99, lng: 44.31, label: 'أ'))
        ..setDropoffPoint(const GeoPoint(lat: 32.61, lng: 44.02, label: 'ب'));

      expect(await c.submit(), isFalse);

      expect(api.driverContactCalls, isEmpty);
      expect(c.driverContact, isNull);
    });

    test('a contact failure does NOT fail the booking', () async {
      // The seat is reserved. Reporting failure because a phone lookup timed
      // out would tell the rider their booking did not happen when it did.
      final api = FakeBookingApi()..driverContactError = Exception('offline');
      final c = BookingController(api: api, trip: tripFixture())
        ..setPickupPoint(const GeoPoint(lat: 31.99, lng: 44.31, label: 'أ'))
        ..setDropoffPoint(const GeoPoint(lat: 32.61, lng: 44.02, label: 'ب'));

      expect(await c.submit(), isTrue);
      expect(c.result, isNotNull);
      expect(c.driverContact, isNull);
    });
  });

  group('confirmation screen', () {
    Widget confirmation({TripContact? contact}) => host(
          BookingConfirmationScreen(
            seatCount: 2,
            fare: 12000,
            departureTime: DateTime.utc(2026, 7, 20, 4, 30),
            originCity: 'Najaf',
            destCity: 'Karbala',
            pickup: const LocationPoint(
                lat: 31.999, lng: 44.3148, label: 'قرية الغدير السكنية'),
            dropoff: const LocationPoint(
                lat: 32.616, lng: 44.0242, label: 'طريق الحر، حي الزيتون'),
            driverContact: contact,
          ),
          extra: [Provider<BookingApi>.value(value: FakeBookingApi())],
        );

    testWidgets('shows the points the rider chose', (t) async {
      await t.pumpWidget(confirmation());
      await t.pump();

      expect(find.text('قرية الغدير السكنية'), findsOneWidget);
      expect(find.text('طريق الحر، حي الزيتون'), findsOneWidget);
    });

    testWidgets('a point opens on a map', (t) async {
      await t.pumpWidget(confirmation());
      await t.pump();

      t.widget<InkWell>(inkFor('قرية الغدير السكنية')).onTap!();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppMapView), findsOneWidget);

      await closeMap(t);
    });

    testWidgets('shows the driver number and both actions', (t) async {
      await t.pumpWidget(
          confirmation(contact: contactFixture(phone: '+9647701234567')));
      await t.pump();

      expect(find.text('+964 770 123 4567'), findsOneWidget);

      t.widget<AppButton>(find.widgetWithText(AppButton, 'واتساب')).onPressed!();
      await t.pump();
      expect(launcher.last.toString(), 'https://wa.me/9647701234567');
    });

    testWidgets('shows no number when the lookup did not resolve', (t) async {
      await t.pumpWidget(confirmation());
      await t.pump();

      expect(renderedText(t).where(_phoneShaped.hasMatch), isEmpty);
    });
  });

  // ── حجوزاتي ──────────────────────────────────────────────────────────────

  group('حجوزاتي', () {
    Future<MyBookingsController> loaded(FakeBookingApi api) async {
      final c = MyBookingsController(api: api);
      await c.load();
      return c;
    }

    FakeBookingApi apiWith({
      TripContact? contact,
      BookingStatus status = BookingStatus.confirmed,
      bool upcoming = true,
    }) =>
        FakeBookingApi()
          ..listMineResult = [
            mineFixture(id: 'b1', status: status, upcoming: upcoming),
          ]
          ..driverContactResult = contact;

    Widget screen(MyBookingsController c) => host(
          const MyBookingsScreen(),
          extra: [ChangeNotifierProvider<MyBookingsController>.value(value: c)],
        );

    testWidgets('an upcoming booking shows the driver number', (t) async {
      final c = await loaded(
          apiWith(contact: contactFixture(phone: '+9647701234567')));
      await t.pumpWidget(screen(c));
      await t.pump();

      expect(find.text('+964 770 123 4567'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'اتصال'), findsOneWidget);
    });

    testWidgets('اتصال dials the driver', (t) async {
      final c = await loaded(
          apiWith(contact: contactFixture(phone: '+9647701234567')));
      await t.pumpWidget(screen(c));
      await t.pump();

      t.widget<AppButton>(find.widgetWithText(AppButton, 'اتصال')).onPressed!();
      await t.pump();

      expect(launcher.last.toString(), 'tel:+9647701234567');
    });

    test('never asks for a cancelled booking — that 403 is expected', () async {
      final api = apiWith(
          status: BookingStatus.cancelled, contact: contactFixture());
      await loaded(api);

      expect(api.driverContactCalls, isEmpty);
    });

    test('never asks for a past booking', () async {
      final api = apiWith(upcoming: false, contact: contactFixture());
      await loaded(api);

      expect(api.driverContactCalls, isEmpty);
    });

    test('cancelling drops the number immediately', () async {
      // The number goes with the booking. Leaving a stale "call your driver"
      // on a seat the rider just gave up is exactly the leak the server rule
      // exists to prevent, arriving via the client's cache instead.
      final api = apiWith(contact: contactFixture(bookingId: 'b1'));
      final c = await loaded(api);
      expect(c.contactFor('b1'), isNotNull);

      await c.cancel('b1');

      expect(c.contactFor('b1'), isNull);
    });

    testWidgets('shows the rider their own two points, tappable', (t) async {
      final c = await loaded(apiWith());
      await t.pumpWidget(screen(c));
      await t.pump();

      expect(find.text('حي السلام'), findsOneWidget);

      t.widget<InkWell>(inkFor('حي السلام')).onTap!();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppMapView), findsOneWidget);

      await closeMap(t);
    });

    testWidgets('never puts a dot beside an Arabic-Indic numeral', (t) async {
      final api = FakeBookingApi()
        ..listMineResult = [mineFixture(id: 'b1', seatCount: 3, fare: 18000)]
        ..driverContactResult = contactFixture();
      final c = await loaded(api);
      await t.pumpWidget(screen(c));
      await t.pump();

      final offenders = renderedText(t)
          .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
          .toList();

      expect(offenders, isEmpty, reason: 'dot touching a digit: $offenders');
    });
  });
}
