/// Taxi app shared design system.
///
/// Single source of truth for theme tokens (colors, typography, spacing,
/// radius, elevation) and the base widget library. Consumed by the rider,
/// driver and admin apps. Screens read everything through `context.*` tokens
/// and these widgets — never a raw hex, font size, spacing or radius.
library shared;

// Theme tokens + ThemeData assembly + `context.*` extensions.
export 'theme/app_theme.dart';

// Theme mode: controller + persistence + the shared MaterialApp shell.
export 'theme/theme_controller.dart';
export 'theme/theme_mode_store.dart';
export 'theme/app_root.dart';

// Base widget library.
export 'widgets/app_icons.dart';
export 'widgets/app_button.dart';
export 'widgets/app_card.dart';
export 'widgets/app_text_field.dart';
export 'widgets/app_badge.dart';
export 'widgets/app_avatar.dart';
export 'widgets/app_scaffold.dart';
export 'widgets/rating_stars.dart';

// Theme preview / gallery (dev + design QA surface).
export 'preview/theme_preview.dart';
export 'preview/galleries.dart';
