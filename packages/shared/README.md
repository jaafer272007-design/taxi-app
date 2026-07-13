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

> Note: icons come from `lucide_icons_flutter` (the Dart-3 maintained Lucide
> fork; class `LucideIcons`). All icon references live in
> `lib/widgets/app_icons.dart`, so swapping the icon pack touches that file only.

## Golden tests (CI-rendered screenshots)

`test/golden_test.dart` snapshots the design system — color tokens, the type
scale, and every base widget — in light and dark, RTL, with the real Cairo font.
Cairo is bundled in `assets/fonts/` (OFL 1.1) and discovered by `google_fonts`,
so it renders offline both here and in the apps — no runtime font fetch. CI
(Flutter pinned to stable) generates the baselines under `test/goldens/`,
mirrors them to `docs/ui-screenshots/`, and uploads them as the `ui-screenshots`
artifact. Once baselines exist, any change that alters rendering fails the
golden test and emits a diff image — a visual regression guard. To intentionally
refresh the baselines, push a commit whose message contains `[update-goldens]`
(or run `flutter test --update-goldens`).
