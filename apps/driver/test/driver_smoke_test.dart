import 'package:driver/driver/driver_controller.dart';
import 'package:driver/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

void main() {
  testWidgets('DriverApp builds and shows the splash before bootstrap resolves',
      (tester) async {
    final themeController =
        await ThemeController.create(store: InMemoryThemeModeStore());
    final auth =
        AuthController(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
    addTearDown(auth.dispose);
    final driver =
        DriverController(api: FakeDriverApi(), picker: FakeDocumentPicker());
    addTearDown(driver.dispose);

    await tester.pumpWidget(DriverApp(
      themeController: themeController,
      authController: auth,
      driverController: driver,
      driverTripApi: FakeDriverTripApi(),
    ));
    await tester.pump();

    expect(find.byType(TaxiApp), findsOneWidget);
    // status starts as unknown → splash spinner (bootstrap not called here).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
