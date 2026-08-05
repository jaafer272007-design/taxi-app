import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/trip_detail_controller.dart';
import 'package:driver/trip/trip_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

/// Getting to the rider: the pickup/dropoff points on a map, and the phone
/// number on the booking row.
///
/// The bug this closes came out of live testing — the driver could read
/// «قرية الغدير السكنية» off the screen and still had no way to reach the
/// door or the person standing at it.
class _FakeLauncher implements LinkLauncher {
  final List<Uri> opened = [];
  bool handles = true;

  Uri? get last => opened.isEmpty ? null : opened.last;

  @override
  Future<bool> open(Uri uri) async {
    if (!handles) return false;
    opened.add(uri);
    return true;
  }
}

void main() {
  late _FakeLauncher launcher;

  setUp(() => launcher = _FakeLauncher());

  Widget host(TripDetailController c) => MultiProvider(
        providers: [
          ChangeNotifierProvider<TripDetailController>.value(value: c),
          Provider<LinkLauncher>.value(value: launcher),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: TripDetailScreen(),
          ),
        ),
      );

  Future<TripDetailController> loaded(FakeDriverTripApi api) async {
    final c = TripDetailController(
      api: api,
      trip: tripFixture(status: TripStatus.open, seatsTotal: 4, seatsAvailable: 2),
      corridor: najafKarbala,
    );
    await c.load();
    return c;
  }

  FakeDriverTripApi apiWith({
    List<TripContact> contacts = const [],
    double pickupLat = 31.9990,
    double pickupLng = 44.3148,
    String pickupLabel = 'قرية الغدير السكنية',
  }) =>
      FakeDriverTripApi()
        ..tripBookingsResult = [
          bookingFixture(
            id: 'b1',
            riderName: 'علي حسن',
            pickupLabel: pickupLabel,
            dropoffLabel: 'طريق الحر، حي الزيتون',
            pickupLat: pickupLat,
            pickupLng: pickupLng,
          ),
        ]
        ..tripContactsResult = contacts;


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
  /// Invoked rather than hit-tested: the booking cards sit well below the fold
  /// of the 800×600 test surface, which is why every interaction test in this
  /// package calls the callback directly.
  Finder inkFor(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );

  group('points on a map', () {
    testWidgets('the pickup opens on a map', (t) async {
      await t.pumpWidget(host(await loaded(apiWith())));
      await t.pump();

      t.widget<InkWell>(inkFor('قرية الغدير السكنية')).onTap!();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppMapView), findsOneWidget);
      expect(find.text('نقطة انطلاق الراكب'), findsOneWidget);

      await closeMap(t);
    });

    testWidgets('the map view hands off to a navigation app', (t) async {
      await t.pumpWidget(host(await loaded(apiWith())));
      await t.pump();
      t.widget<InkWell>(inkFor('قرية الغدير السكنية')).onTap!();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      t.widget<AppButton>(
              find.widgetWithText(AppButton, 'الاتجاهات في تطبيق الخرائط'))
          .onPressed!();
      await t.pump();

      // The driver has to actually DRIVE there — a pin they cannot navigate
      // from is only half the fix.
      expect(launcher.last!.scheme, 'geo');
      expect(launcher.last.toString(), contains('31.999000,44.314800'));

      await closeMap(t);
    });

    testWidgets('a point with no coordinates is not tappable at all', (t) async {
      // 0,0 is Null Island in the Gulf of Guinea. A row that looks tappable and
      // opens a map there is worse than a row that is plainly static — so the
      // InkWell and its map affordance are both absent, not just inert.
      await t.pumpWidget(host(await loaded(
          apiWith(pickupLat: 0, pickupLng: 0, pickupLabel: 'موقع قديم'))));
      await t.pump();

      expect(find.text('موقع قديم'), findsOneWidget);
      expect(inkFor('موقع قديم'), findsNothing);
    });

    testWidgets('a point whose label never geocoded still shows coordinates',
        (t) async {
      await t.pumpWidget(host(await loaded(apiWith(pickupLabel: ''))));
      await t.pump();

      expect(find.text('31.99900, 44.31480'), findsOneWidget);
    });
  });

  group('rider phone number', () {
    testWidgets('shows the number the server returned for this booking',
        (t) async {
      await t.pumpWidget(host(await loaded(apiWith(
          contacts: [contactFixture(bookingId: 'b1', phone: '+9647701234567')]))));
      await t.pump();

      expect(find.text('+964 770 123 4567'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'اتصال'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'واتساب'), findsOneWidget);
    });

    testWidgets('اتصال dials it', (t) async {
      await t.pumpWidget(host(await loaded(apiWith(
          contacts: [contactFixture(bookingId: 'b1', phone: '+9647701234567')]))));
      await t.pump();

      t.widget<AppButton>(find.widgetWithText(AppButton, 'اتصال')).onPressed!();
      await t.pump();

      expect(launcher.last.toString(), 'tel:+9647701234567');
    });

    testWidgets('واتساب opens the chat', (t) async {
      await t.pumpWidget(host(await loaded(apiWith(
          contacts: [contactFixture(bookingId: 'b1', phone: '+9647701234567')]))));
      await t.pump();

      t.widget<AppButton>(find.widgetWithText(AppButton, 'واتساب')).onPressed!();
      await t.pump();

      expect(launcher.last.toString(), 'https://wa.me/9647701234567');
    });

    testWidgets('shows NO contact row when the server returned none', (t) async {
      // The default. A driver looking at somebody else's trip gets a 403 and
      // the row simply is not there — the app never invents a number.
      await t.pumpWidget(host(await loaded(apiWith())));
      await t.pump();

      expect(find.widgetWithText(AppButton, 'اتصال'), findsNothing);
      expect(find.textContaining('+964'), findsNothing);
    });

    testWidgets('a contacts failure leaves the bookings screen working',
        (t) async {
      // Losing the phone column is a missing convenience; turning it into a
      // full-page error would hide the bookings the driver came here for.
      final api = apiWith()..tripContactsError = Exception('boom');
      await t.pumpWidget(host(await loaded(api)));
      await t.pump();

      expect(find.text('علي حسن'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'اتصال'), findsNothing);
    });

    testWidgets('matches the number to the RIGHT booking', (t) async {
      // Two riders, one contact. Keying by bookingId is what stops the app
      // showing rider A's number under rider B's name.
      final api = FakeDriverTripApi()
        ..tripBookingsResult = [
          bookingFixture(id: 'b1', riderId: 'r1', riderName: 'علي حسن'),
          bookingFixture(id: 'b2', riderId: 'r2', riderName: 'حسن كريم'),
        ]
        ..tripContactsResult = [
          contactFixture(
              bookingId: 'b2', userId: 'r2', phone: '+9647709999999'),
        ];
      await t.pumpWidget(host(await loaded(api)));
      await t.pump();

      expect(find.text('+964 770 999 9999'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'اتصال'), findsOneWidget);
    });
  });

  testWidgets('never puts a dot beside an Arabic-Indic numeral', (t) async {
    // The standing rule, swept over the whole rendered screen. Seat count is 3,
    // because formatSeats returns the Arabic dual at 2 and carries no digit at
    // all — a fixture of 1 or 2 renders clean while 3+ is broken.
    final api = FakeDriverTripApi()
      ..tripBookingsResult = [
        bookingFixture(id: 'b1', riderName: 'علي حسن', seatCount: 3, fare: 18000),
      ]
      ..tripContactsResult = [contactFixture(bookingId: 'b1')];
    await t.pumpWidget(host(await loaded(api)));
    await t.pump();

    final offenders = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
        .toList();

    expect(offenders, isEmpty,
        reason: 'a middle dot touches an Arabic-Indic digit: $offenders');
  });
}
