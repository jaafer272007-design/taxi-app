/// App configuration. Values are compile-time overridable with `--dart-define`.
abstract final class AppConfig {
  /// Base URL of the API.
  ///
  /// Default targets the Android emulator's alias for the host machine
  /// (`10.0.2.2` → host `localhost:3000`). Override for a device / staging:
  /// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}
