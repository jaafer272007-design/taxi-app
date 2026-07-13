import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies the theme-mode plumbing: persistence round-trips, the controller
/// defaults to system / loads the saved choice / persists + notifies on change,
/// and TaxiApp binds MaterialApp.themeMode to the controller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('theme mode serialization', () {
    test('every ThemeMode round-trips through its string key', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeFromString(themeModeToString(mode)), mode);
      }
    });

    test('unknown / null keys parse to null (→ caller uses system)', () {
      expect(themeModeFromString(null), isNull);
      expect(themeModeFromString('nonsense'), isNull);
    });
  });

  group('SharedPrefsThemeModeStore', () {
    test('reads null when nothing has been saved', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPrefsThemeModeStore();
      expect(await store.read(), isNull);
    });

    test('write then read returns each mode (real prefs serialization)', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPrefsThemeModeStore();
      for (final mode in ThemeMode.values) {
        await store.write(mode);
        expect(await store.read(), mode);
      }
    });
  });

  group('ThemeController', () {
    test('defaults to system when nothing is persisted', () async {
      final controller =
          await ThemeController.create(store: InMemoryThemeModeStore());
      expect(controller.mode, ThemeMode.system);
    });

    test('loads the persisted mode on create', () async {
      final controller = await ThemeController.create(
        store: InMemoryThemeModeStore(ThemeMode.dark),
      );
      expect(controller.mode, ThemeMode.dark);
    });

    test('setMode updates, notifies once, and persists (survives reload)',
        () async {
      final store = InMemoryThemeModeStore();
      final controller = await ThemeController.create(store: store);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setMode(ThemeMode.light);

      expect(controller.mode, ThemeMode.light);
      expect(notifications, 1);
      expect(await store.read(), ThemeMode.light);

      // A fresh controller over the same store reloads the saved choice —
      // i.e. the selection persists across "restarts".
      final reloaded = await ThemeController.create(store: store);
      expect(reloaded.mode, ThemeMode.light);
    });

    test('setMode to the current mode is a no-op (no notification)', () async {
      final controller = await ThemeController.create(
        store: InMemoryThemeModeStore(ThemeMode.dark),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setMode(ThemeMode.dark);

      expect(notifications, 0);
    });

    test('cycle goes system → light → dark → system', () async {
      final controller =
          await ThemeController.create(store: InMemoryThemeModeStore());
      expect(controller.mode, ThemeMode.system);
      await controller.cycle();
      expect(controller.mode, ThemeMode.light);
      await controller.cycle();
      expect(controller.mode, ThemeMode.dark);
      await controller.cycle();
      expect(controller.mode, ThemeMode.system);
    });
  });

  testWidgets('TaxiApp binds MaterialApp.themeMode to the controller',
      (tester) async {
    final controller = await ThemeController.create(
      store: InMemoryThemeModeStore(ThemeMode.light),
    );

    await tester.pumpWidget(
      TaxiApp(
        title: 'test',
        themeController: controller,
        home: const SizedBox.shrink(),
      ),
    );

    MaterialApp materialApp() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp().themeMode, ThemeMode.light);

    await controller.setMode(ThemeMode.dark);
    await tester.pump();

    expect(materialApp().themeMode, ThemeMode.dark);
  });
}
