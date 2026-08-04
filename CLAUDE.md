# CLAUDE.md — دليل الريبو (تطبيق التكسي المشترك)
> ضعه في **جذر الريبو** باسم `CLAUDE.md`.

## المشروع
منصة نقل **مشترك بالمقعد (pooled)** بين المحافظات، عراقية. **إحنا حالياً بالـ Phase 1.**
النموذج الحالي: **السائق يعلن مسار + الراكب يحجز مقعد**، ممر النجف↔كربلاء، door-to-door، cash، Android.
البريف الكامل: `docs/PHASE1_BUILD_BRIEF.md`. الخطة الكبرى: `docs/PROJECT_PLAN.md`.

## 🚧 حواجز صارمة — لا تبنيها بالـ Phase 1
- ❌ **تجميع النظام (system-pooling)** ولا الطلب الآني بالمطابقة الحية → Phase 2.
- ❌ دفع رقمي/محفظة (cash فقط) → Phase 3.  ❌ iOS → Phase 3.
- ❌ ممرات متعددة، surge، كوبونات → لاحقاً.
- ❌ **microservices** — النظام modular monolith. أضف modules، لا خدمات منفصلة.
> `Trip.createdBy` يبقى `DRIVER` بالـ Phase 1؛ قيمة `SYSTEM` و `SeatRequest` محجوزة للـ Phase 2 — لا تنفّذها الآن.

## الـ Stack
NestJS (monolith، modules نظيفة) · Prisma + PostgreSQL (PostGIS متاح، غير مستخدم بالـ Phase 1) · Redis · Flutter (Android) · React/Next.js (admin) · JWT + WhatsApp OTP · FCM.

## بنية الريبو
```
/services/api      NestJS monolith (modules: auth, driver, corridor, trip, booking, rating, notification, earnings)
/apps/rider        Flutter
/apps/driver       Flutter
/apps/admin        React/Next.js
/packages/shared   أنواع/ثوابت مشتركة + theme (design tokens)
/docs              PROJECT_PLAN.md, PHASE1_BUILD_BRIEF.md, SKILLS_CATALOG.md
```

## ثوابت غير قابلة للتفاوض
- العملة **IQD** (أعداد صحيحة، بلا كسور).  التوقيت **Asia/Baghdad**.  الواجهة **عربي RTL**.
- الهوية = رقم موبايل **+964** عبر **WhatsApp OTP** (لا SMS).
- **مخزون المقاعد transactional** دائماً (row-lock أو `UPDATE ... WHERE seatsAvailable >= seatCount`) — منع overbooking شرط أساسي.
- احترم آلات الحالة بـ `PHASE1_BUILD_BRIEF.md` §3؛ لا تسمح بانتقالات خارجها.

## Design System (Design Tokens) — all Flutter apps (rider, driver, admin)
Never hardcode a color, size, spacing, radius, or font in any screen/widget.
Define all design values in ONE source of truth
(/packages/shared/theme: colors, typography, spacing, radius, app_theme),
consumed via context (e.g. context.colors.primary).
- No raw hex / font size / spacing / radius inside any screen or widget.
- Build a reusable widget library (buttons, cards, inputs) that uses the tokens.
- A full re-skin (colors, fonts, page styling) must be a change to the theme
  files ONLY, never the screens.
- Arabic-first, RTL. Support multiple themes (light/dark) where feasible.

### Palette: "Masar" (مَسار) — locked
Pine + saffron on warm paper. Light `primary #0E5C4A` / `bg #F4F1EA`; dark
`primary #45C6A2` / `bg #0A100E`. Type is Cairo at 34/26/20/17/15/13/12.
- **Accessibility is a locked rule: every foreground/background token pair is
  >= 4.5:1.** It is enforced by `packages/shared/test/contrast_test.dart`, not
  just documented — if a re-skin makes a pair illegible, CI goes red.
- `accent` (#DE8F27) is a **fill-only** token — as ink it is 2.6:1. Use
  `accentText` whenever the saffron must be text or an icon.
- Status backgrounds use the opaque `*Tonal` tokens, never
  `tone.withValues(alpha: …)` — a translucent tint composites over whatever is
  behind it and silently fails contrast depending on where the widget sits.
- The measured ratio table and every deviation from the raw design hand-off (with
  its reason) live in the doc comment at the top of `theme/colors.dart`.

### Numerals (locked decision)
- **Display values render in Arabic-Indic numerals** (`٠١٢٣`) with the Arabic
  thousands separator `٬` (U+066C) and decimal separator `٫` (U+066B) — prices,
  fares, earnings, times, dates, seat counts, ratings.
- **Input fields stay Western** (`0123`) — phone entry and OTP entry. The
  keyboard emits Western digits; converting them mid-typing causes real friction.
- Helpers live in `packages/shared/lib/format/numerals.dart`
  (`toArabicDigits` / `toWesternDigits` / `formatIqd` / `formatPrice` /
  `formatCount` / `formatRating` / `formatTime` / `formatClock` /
  `formatDayShort`). Screens must never hand-roll digit formatting.
- `toWesternDigits` is the inbound direction: normalise anything pasted
  (Arabic-Indic or Persian digits) before parsing or sending to the API — the
  wire format is always Western.
- **Never put a dot-like separator next to an Arabic-Indic numeral.** `٠` IS a
  dot, so `'... · ${formatSeats(3)}'` renders as «٣٠ مقاعد» — thirty — and
  `'${formatSeats(n)} · ${formatPrice(fare)}'` fused the dot onto the fare so
  ٦٬٠٠٠ read as ٦٬٠٠٠٠ on the driver's cash screens. `·` is also **bidi-neutral**,
  so it can be reordered onto the far side of the number. Join with a strong
  Arabic word or letter instead (`بـ` / `لـ` / `الساعة`), or split into two
  widgets. Safe: a separator between two Arabic **words**, or between two digit
  runs (`٣٬٠٠٠ – ١٢٬٠٠٠` renders correctly — same directional run).
  > This class of bug hides in goldens: `formatSeats`/`formatTrips` return the
  > Arabic **dual** («مقعدان») at 2, which carries no digit at all, so a fixture
  > using 1 or 2 renders clean while 3+ is broken. Fixture a count of **3** when
  > a screen shows one. Screen tests should sweep every rendered `Text` for
  > `·` adjacent to `[٠-٩]` — see `apps/driver/test/post_trip_screen_test.dart`.

### Theme mode (light / dark / system)
- Apps ship **light + dark** (both built in `/packages/shared/theme`).
- **Default = `ThemeMode.system`** — follows the phone's setting.
- The user can override to **Light / Dark / System** via a Settings toggle
  (screen TBD). No time-of-day auto-switching.
- The choice **persists across restarts** (`shared_preferences`) and is loaded
  **before the first frame**.
- Plumbing (single source of truth, in `/packages/shared/theme`):
  `ThemeController` (a `ChangeNotifier`, exposed via `provider` — see **State
  management** below) + `ThemeModeStore` (`SharedPrefsThemeModeStore` in prod,
  `InMemoryThemeModeStore` in tests).
- Each app wires it through the shared **`TaxiApp`** shell, which provides the
  controller (`ChangeNotifierProvider`) and drives `MaterialApp.themeMode` from
  it (plus locale `ar` + RTL). Startup:
  `final c = await ThemeController.create(); runApp(TaxiApp(themeController: c, home: ...));`
  **rider is wired first.**

### UI changes — golden screenshots (STANDING RULE, applies automatically)
For **every PR that adds or changes any Flutter screen or UI widget** — do this
without being asked:
- **Add/update golden tests** that render the new/changed screens (or their
  reusable galleries) in **BOTH light and dark**, **RTL**, **Arabic**, with the
  **Cairo font loaded** (see `packages/shared/test/golden_test.dart` for the font
  bootstrap; regenerate with a `[update-goldens]` commit — CI generates the PNGs).
- **Commit the generated PNGs into `docs/ui-screenshots/`** AND **embed them
  inline in the PR description** (markdown images), grouped **by screen** and by
  **light/dark**, so they can be reviewed on a phone with **no download and no
  local run**.
- The CI **`ui-goldens`** job must **upload these images as an artifact on every
  run** (even on success). Keep that behavior in `.github/workflows/ci.yml`.
- In the PR description, **state what is verified vs. not**: which behaviors are
  covered by golden / widget / unit tests, and which still need a **live device
  run** (e.g. real API round-trips, secure storage, push) — so we always know
  what is visually verified vs. behaviorally unverified.

## State management
- **Standard: `ChangeNotifier` + `provider`.** Lightweight, a natural extension
  of the controllers already in place, right-sized for this app.
- **Every feature's state** (auth, user, trips, bookings, …) follows this
  pattern: a `ChangeNotifier` controller holding the logic, exposed with
  `ChangeNotifierProvider` (`.value` for a pre-built instance owned elsewhere,
  `create:` when the widget owns the lifecycle), consumed via `context.watch` /
  `context.read` / `Consumer`.
- Business logic stays in the controller/service, never in the widget.
- **No riverpod / bloc / getx** unless we explicitly revisit this decision.
- Reference: `ThemeController` is provided at the app shell by `TaxiApp` and
  drives `MaterialApp.themeMode`.

## Map picker (خرائط — swappable provider)
- The location picker uses **free OpenStreetMap** tiles via `flutter_map`, but the
  map library is **isolated behind one widget** so the provider can be swapped
  later (e.g. to Google) with a contained change.
- **Single source of truth:** the app depends only on `LocationPoint`
  ({lat,lng,label}) + `AppMapPicker` (interface: `initialCenter`,
  `onPointSelected(LocationPoint)`), both in `/packages/shared/lib/map`.
- **Containment rule:** `flutter_map` + `latlong2` are imported **only** in
  `map/app_map_picker.dart`; `geolocator` **only** in
  `map/geolocator_location_service.dart` (behind the `LocationService`
  interface). Reverse geocoding is behind `ReverseGeocoder` (Nominatim impl).
  **Nothing else in the codebase imports a map/GPS package.**
- To change map provider: rewrite the internals of `app_map_picker.dart` only —
  the booking flow and all callers stay unchanged.
- Tests/goldens pass `usePlaceholderTiles: true` (no network tiles) and inject
  fake `LocationService` / `NullReverseGeocoder`.

## اصطلاحات
- حدود modules واضحة؛ منطق الأعمال بالـ services لا بالـ controllers.
- معالجة أخطاء موحّدة + رسائل عربية للمستخدم.
- كل endpoint يرجع أخطاء واضحة (مقعد غير متاح، سائق غير مُعتمد، إلخ).
- تعليقات/أسماء إنكليزي بالكود؛ نصوص المستخدم عربي.

## CI
- كل PR لازم يعبر CI (أخضر) قبل الدمج. الـ workflow: `.github/workflows/ci.yml`
  يشتغل على كل pull request وعلى push إلى `main`.
- يشغّل لـ `services/api`: `npm ci` → `prisma generate` → `prisma migrate deploy`
  → `npm run build` → `npm test` مقابل Postgres (postgis) + Redis كـ service containers.
- يشغّل لـ `apps/admin`: `lint` → `build` → **Playwright E2E** مقابل ستاك حقيقي
  (Postgres + Redis + الـ API + بناء إنتاجي للوحة). قاعدة بيانات منفصلة
  (`taxi_e2e`) لأن زرع الـ E2E **يمسح صفوفه ويعيد بناءها**. أي فشل يُسقط الـ PR،
  وتُرفع الـ traces/screenshots كـ artifact باسم `admin-e2e-failures`.
  الاختبارات: `apps/admin/e2e/`، والزرع: `services/api/prisma/seed-e2e.ts`.
  التشغيل محلياً: `docs/RUN_LOCAL.md`.
- متغيّرات WhatsApp/FCM غائبة عمداً بالـ CI حتى يُختبر مسار dev-fallback.
- **حماية الفرع (يُفعّلها الأدمن مرة واحدة):** Settings → Branches → Add rule على
  `main` → فعّل "Require status checks to pass" واختَر فحص
  `services/api (build, migrate, test)` — بعدها ما ينــدمج أي PR إلا والـ CI أخضر.

## ترتيب البناء (اختبر بعد كل خطوة)
1. Scaffold + DB + `auth` → دخول OTP يشتغل.
2. `driver` + اعتماد أدمن → سائق يُعتمد.
3. `corridor` + `trip` → سائق يعلن رحلة.
4. `booking` (transactional) → حجز صحيح بلا overbooking.
5. `trip-lifecycle` + `earnings` → رحلة كاملة + نقد مسجّل.
6. `rating` + `notification`.
7. Admin + صقل.
> اختبر رحلة كاملة (حجز→ركوب→نقد→تقييم) قبل الانتقال للخطوة التالية.

## بنود للتحقق قبل الاعتماد (Phase 0)
- مزوّد الخرائط (OSM/OSRM مقابل Google) + تغطية ممر النجف↔كربلاء + الأسعار.
- إصدارات حزم Flutter الحالية.
- إعداد WhatsApp Business Cloud API (أعِد استخدام إعداد Sehat Beitak).

---
> **الـ skills (تسويق/تصميم/ملفات):** كتالوج التفعيل التلقائي انتقل إلى
> `docs/SKILLS_CATALOG.md` — مرجع لأعمال النمو/التصميم، مو من قواعد بناء الكود.
