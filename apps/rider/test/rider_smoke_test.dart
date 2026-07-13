import 'package:flutter_test/flutter_test.dart';
import 'package:rider/main.dart';
import 'package:shared/shared.dart';

/// Compile + smoke check for the rider app shell: it builds, wires the shared
/// TaxiApp, and shows the placeholder home. (Theme persistence itself is
/// covered by packages/shared/test/theme_controller_test.dart.)
void main() {
  testWidgets('RiderApp builds and shows the placeholder home', (tester) async {
    final controller =
        await ThemeController.create(store: InMemoryThemeModeStore());

    await tester.pumpWidget(RiderApp(themeController: controller));
    await tester.pump();

    expect(find.byType(TaxiApp), findsOneWidget);
    expect(find.text('تطبيق الراكب'), findsOneWidget);
  });
}
