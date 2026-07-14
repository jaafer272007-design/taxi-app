import 'package:driver/driver/driver_controller.dart';
import 'package:driver/driver/driver_models.dart';
import 'package:driver/driver/vehicle_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

Widget _host(DriverController c) =>
    ChangeNotifierProvider<DriverController>.value(
      value: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: VehicleFormScreen(),
        ),
      ),
    );

Future<DriverController> _ctrl(FakeDriverApi api) async {
  final c = DriverController(api: api, picker: FakeDocumentPicker());
  await c.load();
  return c;
}

/// Invoke the save button's real onPressed (avoids positional hit-testing).
void _save(WidgetTester t) =>
    t.widget<AppButton>(find.byType(AppButton)).onPressed!();

void main() {
  testWidgets('empty form shows required errors and does not call the API',
      (t) async {
    final api = FakeDriverApi()
      ..profile = profileFixture(status: DriverStatus.pending);
    final c = await _ctrl(api);
    await t.pumpWidget(_host(c));

    _save(t);
    await t.pumpAndSettle();

    expect(find.text('مطلوب'), findsWidgets); // make/model/plate/color
    expect(find.text('أدخل رقماً'), findsOneWidget); // seats empty
    expect(api.vehicleCalls, 0);
  });

  testWidgets('too many seats is rejected (no API call)', (t) async {
    final api = FakeDriverApi()
      ..profile = profileFixture(status: DriverStatus.pending);
    final c = await _ctrl(api);
    await t.pumpWidget(_host(c));

    await t.enterText(find.byType(TextField).at(0), 'Toyota');
    await t.enterText(find.byType(TextField).at(1), 'Corolla');
    await t.enterText(find.byType(TextField).at(2), '12345');
    await t.enterText(find.byType(TextField).at(3), 'أبيض');
    await t.enterText(find.byType(TextField).at(4), '99');
    _save(t);
    await t.pumpAndSettle();

    expect(find.text('عدد غير منطقي'), findsOneWidget);
    expect(api.vehicleCalls, 0);
  });

  testWidgets('valid form calls saveVehicle with the parsed seats', (t) async {
    final api = FakeDriverApi()
      ..profile = profileFixture(status: DriverStatus.pending);
    final c = await _ctrl(api);
    await t.pumpWidget(_host(c));

    await t.enterText(find.byType(TextField).at(0), 'Toyota');
    await t.enterText(find.byType(TextField).at(1), 'Corolla');
    await t.enterText(find.byType(TextField).at(2), '12345');
    await t.enterText(find.byType(TextField).at(3), 'أبيض');
    await t.enterText(find.byType(TextField).at(4), '4');
    _save(t);
    await t.pumpAndSettle();

    expect(api.vehicleCalls, 1);
    expect(c.profile!.vehicle!.seats, 4);
  });
}
