import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen [ThemeMode] across app restarts.
///
/// Abstracted so the [ThemeController] can be unit-tested without the
/// shared_preferences platform plugin (use [InMemoryThemeModeStore] in tests).
abstract interface class ThemeModeStore {
  /// Returns the saved mode, or `null` if the user has never chosen one
  /// (in which case the app defaults to [ThemeMode.system]).
  Future<ThemeMode?> read();

  /// Persists [mode].
  Future<void> write(ThemeMode mode);
}

/// Serializes a [ThemeMode] to its stable string key (`system`/`light`/`dark`).
String themeModeToString(ThemeMode mode) => mode.name;

/// Parses a persisted key back to a [ThemeMode]; `null` for unknown/absent
/// values so callers fall back to [ThemeMode.system].
ThemeMode? themeModeFromString(String? value) => switch (value) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };

/// Default production store backed by `shared_preferences`.
class SharedPrefsThemeModeStore implements ThemeModeStore {
  const SharedPrefsThemeModeStore();

  /// Preferences key. Stable — changing it drops existing users' choice.
  static const String key = 'theme_mode';

  @override
  Future<ThemeMode?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return themeModeFromString(prefs.getString(key));
  }

  @override
  Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, themeModeToString(mode));
  }
}

/// In-memory store for tests (and previews). Not persistent.
class InMemoryThemeModeStore implements ThemeModeStore {
  InMemoryThemeModeStore([this._value]);

  ThemeMode? _value;

  @override
  Future<ThemeMode?> read() async => _value;

  @override
  Future<void> write(ThemeMode mode) async => _value = mode;
}
