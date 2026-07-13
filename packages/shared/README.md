# packages/shared — Design System

Single source of truth for the visual language of every app (rider, driver,
admin). Screens read **only** tokens and base widgets from here — never a raw
hex, font size, spacing or radius.

## Layout

```
lib/
  theme/
    colors.dart       AppColors      — semantic color tokens (light + dark)
    typography.dart   AppTypography  — Cairo type scale (Arabic-first) + .tabular figures
    spacing.dart      AppSpacing     — 4/8 rhythm (xs…xl4)
    radius.dart       AppRadii       — sm/md/lg/pill
    elevation.dart    AppElevation   — soft card shadow
    app_theme.dart    AppTheme.light()/dark() + `context.*` token access
  widgets/
    app_icons.dart    AppIcons       — the ONLY file that imports the icon package
    app_button.dart   AppButton      — primary/secondary/ghost/danger, press+loading+disabled
    app_card.dart     AppCard
    app_text_field.dart AppTextField — label + helper + error
    app_badge.dart    AppBadge / AppPill (success/warning/danger/info/neutral)
    app_avatar.dart   AppAvatar      — initials
    rating_stars.dart RatingStars
    app_scaffold.dart AppScaffold    — safe areas, RTL, titled app bar
  preview/
    theme_preview.dart ThemePreviewApp / ThemePreview — renders ALL tokens + widgets
  shared.dart          barrel export
example/               runnable app: `flutter run` → the Theme Preview
```

## Usage

```dart
import 'package:shared/shared.dart';

MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  locale: const Locale('ar'),
  builder: (c, child) =>
      Directionality(textDirection: TextDirection.rtl, child: child!),
);

// Inside any widget:
Container(
  padding: EdgeInsets.all(context.space.lg),
  decoration: BoxDecoration(
    color: context.colors.surface,
    borderRadius: context.radii.mdAll,
    boxShadow: context.elevation.card,
  ),
  child: Text('مرحبا', style: context.text.title),
);
```

## Preview the whole system

```bash
cd packages/shared/example
flutter pub get
flutter run          # light + dark, side by side, RTL
```

## The re-skin rule

A full re-skin (colors, fonts, page styling) is a change to the **token files
only**. Change `primary` in `lib/theme/colors.dart` and every screen, button
and badge in all three apps updates — no screen edits. `test/reskin_test.dart`
guards this.

> Note: `lucide_icons` is pinned in `pubspec.yaml`; if the first `flutter pub
> get` asks for a different version, bump it there — all icon references live in
> `lib/widgets/app_icons.dart`, so nothing else changes.
