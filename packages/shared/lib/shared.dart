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
export 'widgets/app_segmented_control.dart';
export 'widgets/app_confirm_dialog.dart';
export 'widgets/rating_stars.dart';
export 'widgets/onboarding_header.dart';
export 'widgets/otp_input.dart';

// Shared screens (reused across apps).
export 'settings/settings_screen.dart';

// Networking layer (base URL + JWT interceptor + Arabic error mapping) and the
// Iraqi-phone helper — shared by the rider & driver apps.
export 'net/api_exception.dart';
export 'net/api_client.dart';
export 'net/token_store.dart';
export 'net/iraqi_phone.dart';

// Auth: the OTP session controller + API + user model, shared by both apps.
// Each app keeps its own thin onboarding screens (app-specific copy).
export 'auth/auth_user.dart';
export 'auth/auth_api.dart';
export 'auth/auth_controller.dart';

// Theme preview / gallery (dev + design QA surface).
export 'preview/theme_preview.dart';
export 'preview/galleries.dart';
