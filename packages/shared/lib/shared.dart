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
export 'widgets/app_city_field.dart';
export 'widgets/rating_stars.dart';
export 'widgets/onboarding_header.dart';
export 'widgets/otp_input.dart';

// Masar signature components (PR 2): the route-rail motif, seats drawn as
// seats, and the floating pill nav that replaces Material's bottom bar.
export 'widgets/route_rail.dart';
export 'widgets/route_search_card.dart';
export 'widgets/seat_glyphs.dart';
export 'widgets/floating_pill_nav.dart';
export 'widgets/on_primary_chip.dart';
export 'widgets/seat_count_picker.dart';

// Shared domain constants (canonical Iraqi cities, kept in sync with the API).
export 'constants/iraqi_cities.dart';

// Numeral formatting — Arabic-Indic for display, Western for phone/OTP entry.
// The per-app `trip/trip_format.dart` copies were deleted in PR 2, so these are
// now the only implementations and screens read them from this barrel.
export 'format/numerals.dart';

// Shared screens (reused across apps).
export 'settings/settings_screen.dart';

// Map location picker. flutter_map/latlong2 live ONLY inside app_map_picker.dart
// and geolocator ONLY inside geolocator_location_service.dart, so the map/GPS
// providers stay swappable — the rest of the app depends on these types only.
export 'map/location_point.dart';
export 'map/location_service.dart';
export 'map/geolocator_location_service.dart';
export 'map/reverse_geocoder.dart';
export 'map/app_map_picker.dart';

// Networking layer (base URL + JWT interceptor + Arabic error mapping) and the
// Iraqi-phone helper — shared by the rider & driver apps.
export 'net/api_exception.dart';
export 'net/api_client.dart';
export 'net/token_store.dart';
export 'net/iraqi_phone.dart';

// Auth: the OTP session controller + API + user model, shared by both apps.
export 'auth/auth_user.dart';
export 'auth/auth_api.dart';
export 'auth/auth_controller.dart';

// Onboarding screens — ONE implementation for both apps. They used to be
// duplicated per app, which meant every fix had to be applied twice and a fix
// that landed in only one was invisible until it bit. The four sentences that
// genuinely differ are passed in as OnboardingCopy; nothing here knows whether
// it is running in the rider or the driver app.
export 'auth/onboarding/onboarding_copy.dart';
export 'auth/onboarding/phone_screen.dart';
export 'auth/onboarding/otp_screen.dart';
export 'auth/onboarding/name_screen.dart';
export 'auth/onboarding/onboarding_flow.dart';
export 'auth/onboarding/splash_screen.dart';

// Theme preview / gallery (dev + design QA surface).
export 'preview/theme_preview.dart';
export 'preview/galleries.dart';
