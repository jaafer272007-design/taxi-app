# apps/rider — Rider (passenger) app

Flutter (Android), Arabic RTL. Consumes the design system in
[`/packages/shared`](../../packages/shared).

## Status (Phase 1)

Scaffold only. Wired so far:

- **Theme mode** — `main.dart` loads the persisted `ThemeMode` via
  `ThemeController.create()` (defaults to `ThemeMode.system`) and hands it to
  the shared `TaxiApp`, which binds `MaterialApp.themeMode`. The choice persists
  across restarts (`shared_preferences`). No settings screen yet.
- `home.dart` is a temporary placeholder (real screens come next, screen by
  screen).

## Run

```bash
cd apps/rider
flutter pub get
flutter run       # Android
```
