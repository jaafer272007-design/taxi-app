import 'package:flutter/material.dart';

import 'theme_mode_store.dart';

/// Holds the current [ThemeMode] and persists changes.
///
/// This is the project's initial app-state approach: a plain [ChangeNotifier]
/// with no external state-management dependency. It composes cleanly if the
/// team later adopts provider/riverpod (wrap this controller in a
/// `ChangeNotifierProvider` / expose it from a provider).
///
/// Default mode is [ThemeMode.system] (follows the phone). The user's override
/// (Light / Dark / System) persists across restarts; there is no time-of-day
/// auto-switching.
class ThemeController extends ChangeNotifier {
  ThemeController({
    required ThemeModeStore store,
    ThemeMode initialMode = ThemeMode.system,
  })  : _store = store,
        _mode = initialMode;

  final ThemeModeStore _store;
  ThemeMode _mode;

  /// The active theme mode. Bind `MaterialApp.themeMode` to this (see
  /// [TaxiApp]) so the whole app reacts when it changes.
  ThemeMode get mode => _mode;

  /// Builds a controller and loads the persisted mode (defaults to
  /// [ThemeMode.system]). Call once at startup, before `runApp`:
  ///
  /// ```dart
  /// WidgetsFlutterBinding.ensureInitialized();
  /// final controller = await ThemeController.create();
  /// runApp(TaxiApp(themeController: controller, home: const RiderHome()));
  /// ```
  ///
  /// Pass [store] in tests (e.g. [InMemoryThemeModeStore]); production uses
  /// [SharedPrefsThemeModeStore].
  static Future<ThemeController> create({ThemeModeStore? store}) async {
    final resolvedStore = store ?? const SharedPrefsThemeModeStore();
    final saved = await resolvedStore.read();
    return ThemeController(
      store: resolvedStore,
      initialMode: saved ?? ThemeMode.system,
    );
  }

  /// Sets [mode], notifies listeners immediately (responsive UI), then persists.
  /// No-op when unchanged.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _store.write(mode);
  }

  /// Cycles System → Light → Dark → System. Handy for a future settings toggle
  /// or a dev affordance.
  Future<void> cycle() => setMode(switch (_mode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      });
}
