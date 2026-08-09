import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider/main.dart';
import 'package:rider/trip/trip_search_controller.dart';
import 'package:shared/shared.dart';

import 'package:rider/pool/seat_requests_controller.dart';

import 'support/booking_fakes.dart';
import 'support/fakes.dart';
import 'support/pool_fakes.dart';
import 'support/trip_fakes.dart';

void main() {
  testWidgets('RiderApp builds and shows the splash before bootstrap resolves',
      (tester) async {
    final themeController =
        await ThemeController.create(store: InMemoryThemeModeStore());
    final auth =
        AuthController(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
    addTearDown(auth.dispose);
    final trips = TripSearchController(api: FakeTripApi());
    final seatRequestApi = FakeSeatRequestApi();

    await tester.pumpWidget(RiderApp(
      notificationsController:
          NotificationsController(api: FakeNotificationApi()),
      themeController: themeController,
      authController: auth,
      tripSearchController: trips,
      bookingApi: FakeBookingApi(),
      seatRequestApi: seatRequestApi,
      seatRequestsController: SeatRequestsController(api: seatRequestApi),
    ));
    await tester.pump();

    expect(find.byType(TaxiApp), findsOneWidget);
    // status starts as unknown → splash spinner (bootstrap not called here).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
