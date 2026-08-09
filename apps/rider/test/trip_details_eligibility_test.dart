import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/booking_api.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/trip/trip_details_screen.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';
import 'support/fakes.dart';
import 'support/trip_fakes.dart';

void main() {
  Future<AuthController> authWith(Gender gender) async {
    final api = FakeAuthApi()..meResult = fakeUser(name: 'راكب', gender: gender);
    final auth = AuthController(api: api, tokenStore: InMemoryTokenStore('jwt'));
    addTearDown(auth.dispose);
    await auth.bootstrap();
    return auth;
  }

  Widget host(AuthController auth, Widget child, {BookingApi? booking}) {
    Widget app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );
    if (booking != null) {
      app = Provider<BookingApi>.value(value: booking, child: app);
    }
    return ChangeNotifierProvider<AuthController>.value(value: auth, child: app);
  }

  testWidgets('male rider cannot book a women/family trip: disabled + note',
      (tester) async {
    final auth = await authWith(Gender.male);
    await tester.pumpWidget(host(
      auth,
      TripDetailsScreen(trip: tripFixture(tripType: TripType.womenFamily)),
    ));

    expect(find.textContaining('مخصّصة للركّاب من النساء'), findsOneWidget);
    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'رحلة نسائية-عائلية'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('female rider can book a women/family trip', (tester) async {
    final auth = await authWith(Gender.female);
    await tester.pumpWidget(host(
      auth,
      TripDetailsScreen(trip: tripFixture(tripType: TripType.womenFamily)),
    ));

    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'احجز مقعد'),
    );
    expect(btn.onPressed, isNotNull);
    expect(find.textContaining('مخصّصة للركّاب من النساء'), findsNothing);
  });

  testWidgets('any rider can book a general trip', (tester) async {
    final auth = await authWith(Gender.male);
    await tester.pumpWidget(host(auth, TripDetailsScreen(trip: tripFixture())));

    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'احجز مقعد'),
    );
    expect(btn.onPressed, isNotNull);
  });

  // ── the no-show block ────────────────────────────────────────────────────
  //
  // The server is the gate; this bar exists so the rider learns BEFORE filling
  // in pickup, dropoff and seat count. So what is pinned here is that the CTA
  // is *replaced* — a disabled button beside a notice would still read as
  // "try again", and the whole point is to send them somewhere else.

  testWidgets('a blocked rider gets the notice INSTEAD of the book button',
      (tester) async {
    final auth = await authWith(Gender.male);
    final booking = FakeBookingApi()
      ..eligibilityResult = BookingEligibility(
        blocked: true,
        // 3, never 2: formatTimes(2) is the Arabic dual «مرتين», which carries
        // no digit at all — a fixture of 2 renders clean past a broken
        // numeral path (CLAUDE.md).
        noShowCount: 3,
        blockedUntil: DateTime.utc(2026, 8, 15, 9),
      );

    await tester.pumpWidget(host(
      auth,
      TripDetailsScreen(trip: tripFixture()),
      booking: booking,
    ));
    await tester.pumpAndSettle();

    expect(booking.eligibilityCalls, 1);
    expect(find.text('تم إيقاف الحجز مؤقتاً'), findsOneWidget);
    expect(find.textContaining('٣ مرات'), findsOneWidget);
    expect(find.textContaining('١٥ آب'), findsOneWidget);
    // Existing bookings survive a block — saying so here is what stops the
    // support call.
    expect(find.textContaining('حجوزاتك الحالية لم تتأثر'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'احجز مقعد'), findsNothing);
  });

  testWidgets('an unblocked rider keeps the button after the check returns',
      (tester) async {
    final auth = await authWith(Gender.male);
    final booking = FakeBookingApi(); // eligibilityResult defaults to ok

    await tester.pumpWidget(host(
      auth,
      TripDetailsScreen(trip: tripFixture()),
      booking: booking,
    ));
    await tester.pumpAndSettle();

    expect(booking.eligibilityCalls, 1);
    expect(find.text('تم إيقاف الحجز مؤقتاً'), findsNothing);
    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'احجز مقعد'),
    );
    expect(btn.onPressed, isNotNull);
  });

  // Fail-OPEN, against a real socket rather than a mock.
  //
  // This is the direction that matters: guessing "blocked" on a dropped
  // request would lock a rider out of the product over a bad minute of
  // network, and the server would have let them book. Port 1 refuses
  // instantly, so this is fast and needs nothing running.
  test('eligibility() answers "allowed" when the request fails', () async {
    final dio = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:1',
      connectTimeout: const Duration(seconds: 2),
    ));
    final result = await DioBookingApi(dio).eligibility();
    expect(result.blocked, isFalse);
  });
}
