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

### Glyph coverage
The bundled Cairo has **no arrow glyphs** — `←` / `→` render as a tofu box (seen
in a golden). Join cities with a word (`النجف إلى كربلاء`) or draw the direction
with `RouteRail`, never with an arrow character. Same caution for any symbol not
already in use: check it in a golden before it ships.

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
- **Phone numbers and coordinates stay Western, forced LTR** — a documented
  exception, not an oversight. A phone number is an **identifier** to be dialled
  and matched against the device's contact list, not a quantity to be read; and
  `+٩٦٤ ٧٧١…` in an RTL line adds a `+` sign to the bidi hazard below. Format
  via `ContactLink.display` (`+964 771 234 5678`), render inside
  `Directionality(TextDirection.ltr)`. Same for lat/lng: a machine format for
  another app to parse. Rationale in `docs/PHASE1_BUILD_BRIEF.md` → `trip-contacts`.
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
- **The hazard applies on the WEB too — measured in Chromium, not assumed.**
  The admin panel shipped `plate · ${formatSeats(4)}`, and the browser painted
  it exactly like the Flutter bug: bidi resolves the `·` to the **right** of the
  digit, which is precisely where a `٠` sits (digits run left-to-right inside an
  RTL line), and Cairo draws `·` and `٠` as the same small mid-height dot. The
  separation was **3px against a 7px digit** — `E2E-1001 · ٤ مقاعد` and
  `E2E-1001 ٤٠ مقاعد` (four seats vs forty) were all but indistinguishable.
  So the rule is one rule, not a Flutter rule: **same hazard, same fixes**
  (join with a strong Arabic word/letter, or split into separate elements and
  let layout do the separating — on web, a flex `gap` rather than a character).
  - **A string assertion cannot catch this, on any platform.** `innerText` and
    `find.text` return **logical** order; the reordering happens at layout. The
    text check «`٤ مقاعد` present, `٤٠ مقاعد` absent» passed against the broken
    page. The guard has to measure **painted glyph positions** — see
    `apps/admin/e2e/numerals.spec.ts`, which walks every character's client rect,
    sorts by x to recover visual order, and fails when a dot-like glyph lands
    within 6px of an Arabic-Indic digit. It runs on every panel page in CI.
  - Exempt from that sweep, deliberately: `٬` (U+066C) and `٫` (U+066B) are
    *part* of the number and are supposed to touch the digits.

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
- **A golden that interacts must pump past the animation.** `AppCard` and
  `AppButton` cross-fade over **120ms**, and Flutter reuses the widget at a list
  position across a rebuild — so a golden taken after a tap can catch a colour
  mid-`lerp`. The «سابقة» screenshot shipped with the rate button still wearing
  the *cancel* button's danger tint (measured fill `#F9EDEC` = `lerp(dangerTonal,
  surface, 0.27)` — 64ms in) and looked like a design bug that did not exist.
  Pump **≥ 2 frames of 300ms** after any tap, and read the PNG before believing
  it. A screenshot of a frame nobody ever sees is worse than no screenshot.
- **Look at the images, don't just let CI regenerate them.** Every visual bug
  found here so far — the tofu arrow, the fused `٠` dot, this one — was found by
  opening the PNG. The test passing means the PNG matches itself.
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

## Refresh & polling (locked decision)

The app used to fetch once on open and never learn that anything changed: a
rider could not see a trip posted a minute ago, and a driver could cancel a
trip with booked seats and the riders found out by arriving at the pickup point.

- **Polling, not WebSocket.** Users are on unreliable Iraqi mobile networks. A
  poll recovers from a dropped connection by simply succeeding next time; a
  socket has to notice it died, back off, reconnect and re-sync — and a socket
  that *thinks* it is connected is worse than none, because the screen looks
  live while it is frozen. Revisit for Phase 2 live matching.
- **One implementation:** `Poller` (pure Dart, no Flutter — which is what makes
  start/pause/resume unit-testable) + `PollingScope` (the widget that decides
  when it may run). No screen writes its own `Timer`.
- **Never poll a screen nobody is looking at.** `PollingScope` gates on the
  conjunction of three things, and each one alone leaves a real hole:
  the app is **visible** (`appIsVisible`, via `WidgetsBindingObserver`), this
  route is on top (`appRouteObserver`, registered by `TaxiApp`), and this tab is
  selected (`TickerMode` — an `IndexedStack` keeps every tab mounted and
  building, so the shells wrap each tab in `TickerMode(enabled: isSelected)`).
- **Gate on VISIBLE, never on FOCUSED. `AppLifecycleState.inactive` is a
  visible state.** This one shipped and killed polling everywhere. The gate read
  `state == AppLifecycleState.resumed`, but `inactive` means *visible without
  input focus*: on the web a window you clicked away from (the engine binds
  `window.addEventListener('blur')` straight to it), on Android split screen
  where the other app is current, a system dialog, or the notification shade.
  Only `hidden` / `paused` / `detached` mean "not on screen".
  - The blast radius is the whole app, because `_foreground` is ANDed **outside**
    the `pauseWhenObscured` escape hatch — so one blur also took down the
    app-wide notification badge, the one poll that is supposed to survive
    everything. Opening the driver app to post a trip was enough to do it.
  - Measured in Chromium against the real web build: 4 requests/40s focused,
    **0** while blurred-but-visible, and it stayed at zero until focus returned.
  - Seed the flag from `WidgetsBinding.instance.lifecycleState` at mount.
    `addObserver` does not replay the current state and the binding only
    re-sends on a *change*, so an assumed `true` is never corrected.
- **A widget test cannot discover this class of bug, only pin it.** A widget
  test decides for itself what `inactive` means, so it will happily agree with
  whatever the code believes — the old suite asserted *"inactive is enough to
  stop polling"* and stayed green the entire time polling was dead. Two layers
  are needed and both are now in CI: `polling_scope_test.dart` drives lifecycle
  through the **real binding** (a `flutter/lifecycle` platform message, not a
  direct call on the State — which also proves the scope is registered at all),
  and `apps/rider/e2e/polling_lifecycle.mjs` runs the real `flutter build web`
  in Chromium and asserts requests keep flowing across a genuine window blur.
- **Every await on the poll path is BOUNDED, and `isTicking` is not a health
  check.** `Poller._inFlight` is a latch: until an `onPoll` future completes,
  every later tick returns at the guard. One await that never finishes therefore
  silenced that screen for as long as it stayed open — and `isTicking` went on
  reporting true, a silent failure that reported itself as healthy. Measured in
  Chromium: **one** hung read, then the scope was dead, and it **never recovered
  even after the fault cleared**.
- **`connectTimeout + receiveTimeout` is NOT a total request bound.** Believing
  it was is the trap. On web it happens to be one (`dio_web_adapter` sets
  `xhr.timeout = connect + receive`; a stalled endpoint was measured aborting at
  15s, one request at a time). **On Android it is not:** `receiveTimeout` is an
  inter-chunk idle timer, re-armed on every chunk (dio
  `response_stream_handler.dart`: "between received chunks"), so a peer dripping
  a byte every 14s keeps one request alive for ever.
  - So the total bound is ours: `kRequestDeadline` (45s) armed by the **first**
    interceptor in `ApiClient`. Dio reads `requestOptions.cancelToken` *lazily*,
    inside the closure it wraps each interceptor in (`dio_mixin.dart`
    `requestInterceptorWrapper` → `listenCancelForAsyncTask`, i.e.
    `Future.any([work, cancelToken.whenCancel])`), so a token armed there bounds
    every later interceptor — including the JWT read — and the adapter.
  - It **cancels**, it does not merely give up. That is what makes the whole
    design safe against "polls never stack": when the poller recovers there is
    provably nothing still on the wire. `Future.timeout` does NOT cancel
    (dart-sdk `future.dart` — it completes a *new* future and leaves the source
    running), so a watchdog alone would have allowed exactly the overlap the
    rule forbids.
  - `kTokenReadTimeout` (5s) bounds the JWT read specifically and **rejects**
    rather than continuing unauthenticated — a 401 would read as "your session
    expired" and bounce the user to login over a keystore hiccup. It rejects
    with a `DioException` so `mapDioError` still speaks Arabic; an error thrown
    out of an interceptor is not one, and would sail past every mapper.
  - `kPollWatchdog` (150s) is the last resort for an await nobody bounded. Its
    value is arithmetic, not taste: the slowest `onPoll` is حجوزاتي, which awaits
    `listMine` and *then* fans out to the contact endpoints — two sequential
    request phases, so 2 × 45s = 90s, and 150s clears that.
  - Ask `isHealthy`, not `isTicking`. `stalls` counts watchdog trips and stays 0
    in a healthy app.
- **Inducing a hang needs no test hook.** On web `flutter_secure_storage`
  decrypts the JWT with `crypto.subtle.decrypt`, so replacing that one browser
  API with a promise that never resolves hangs the token read exactly as a
  wedged platform channel would — in the real production build.
  `apps/rider/e2e/poll_recovery.mjs` does that and counts token-read ATTEMPTS
  (nothing reaches the wire once the read is bounded, because the request is
  rejected before the adapter): **1 attempt = latched, one per interval =
  alive.** Measured 1 before the fix, 3 after.
- **Never poll a terminal screen.** `enabled:` is false when there is nothing
  left to learn — a settled trip, a history of finished bookings.
- **A background refresh is silent, always.** Controllers take `load({silent})`
  and expose `refreshSilently()`: no spinner, and **on failure the last good
  data stays on screen and nothing is reported**. The user did not ask for the
  refresh and must not be told it failed. Only an explicit, visible load
  (first open, retry button) may show an error page.
- **Pull-to-refresh calls the silent path too** — the `RefreshIndicator` is
  already the spinner, and a non-silent call takes the list away under the
  user's finger and can replace it with a full-page error.
- Polls never stack: a tick while a request is in flight is skipped, not queued.

| Screen | Interval | Live while |
|---|---|---|
| rider — نتائج البحث | **15s** | always on screen (an «الآن» trip appears *and expires* inside 30 min) |
| rider — حجوزاتي | **30s** | any upcoming, non-cancelled, non-completed booking |
| driver — رحلاتي | **20s** | any trip `OPEN` / `LOCKED` / `EN_ROUTE` |
| driver — تفاصيل الرحلة | **20s** | `OPEN` / `LOCKED` / `EN_ROUTE` |
| driver — أرباحي | — | never polls; `refreshWhenVisible` only |
| both — notification badge | **30s** | authenticated (app-shell wide, so a cancellation reaches the user on *any* screen) |

Every list screen (both apps) has pull-to-refresh regardless of whether it polls.

- **"Does it tick" and "is it stale" are DIFFERENT questions, and answering only
  the first left three screens frozen.** Every list loads once behind
  `if (!c.hasLoaded) c.load()` and then never again, so a screen with no reason
  to *tick* also had no way to ever *reload*. `PollingScope(refreshWhenVisible:
  true)` re-asks exactly once when the screen comes back into view, independent
  of `enabled`; it fires on transitions only, so the screen's own `initState`
  still owns the first, visible load.
  - driver **رحلاتي** shipped with no `PollingScope` at all. The rider's booking
    notification arrived (that poll is app-wide) while the card behind it kept
    the seat count from whenever the tab was opened — a driver decides whether
    to wait for another passenger on that number. Measured in Chromium:
    **stale for 60s+ without the scope, correct in ~20s with it.**
  - driver **أرباحي** is deliberately `enabled: false` — earnings move only when
    the driver completes a trip, on another screen — but it needed
    `refreshWhenVisible`, or it showed the total from before their own trip
    until the app was restarted.
  - rider **حجوزاتي** polls only while it holds a live booking, which is right,
    but a rider who opened it *before* booking anything had an empty list, no
    tick, and no reload — so their first booking never appeared.
- **A widget test cannot find this class of bug.** It asserts what a controller
  does when something calls it; here nothing was calling it. The guard is
  `apps/driver/e2e/my_trips_refresh.mjs`, which runs BOTH real web builds against
  one real backend, books a seat over the API, and asserts the driver's card
  changes with **no interaction at all**. Verified by deletion: remove the scope
  and it fails.
  - **Assert the rendered Arabic, not a digit.** The first version of that spec
    booked 2 seats and looked for «٢» — which can never appear, because
    `SeatGlyphs.label(2)` is the dual «مقعدان متاحان» and the label always ends
    «من ٤» with the total. It books **1** seat and matches «٣ مقاعد متاحة».
    Same trap as the golden fixtures: at 2 there is no numeral to see.

### The admin panel (`/apps/admin`)

Same rule, different mechanism: the panel is React Server Components, so a
"refresh" is `router.refresh()` — the RSC payload is re-fetched and re-rendered
with scroll position, open dialogs and client state intact. There is no client
data layer to keep in sync.

- One component, `RefreshBar`, does the polling **and** renders the manual
  control («تحديث» + «آخر تحديث الساعة …»). Every polled view gets it; nothing
  else sets a timer.
- **السائقون — 20s.** The one that matters: a driver stuck at «بانتظار
  المراجعة» cannot post a trip until an admin sees them.
  **لوحة المعلومات — 60s.** Figures watched over a shift.
  **الممرات — NOT polled**, deliberately: 306 rows that only change when an
  admin changes them.
- Pauses on `document.visibilityState === "hidden"`, resumes on
  `visibilitychange`/`focus` with one immediate catch-up refresh. A failed
  refresh leaves the rendered tree and says nothing.
- The **pending-drivers badge** on the Drivers nav item comes from the layout's
  dashboard aggregate, so it is as fresh as whatever view is open — on
  /drivers and /dashboard it follows their beat; on /corridors it is as of page
  load. Zero draws nothing.
- `?refreshMs=` (floored at 1s) overrides the beat for one tab. It exists so
  `e2e/refresh.spec.ts` can prove "it stopped while hidden" in seconds without
  a build-time flag that would fire `router.refresh()` under every other spec's
  clicks.

## In-app notifications

Stored notifications are the half of the event system that works today — FCM
push is written but blocked on Firebase credentials. **One emitter, two sinks:**
`NotificationService.send()` writes the row *then* attempts the push; nothing
sends an event any other way. Details and the per-side event matrix are in
`docs/PHASE1_BUILD_BRIEF.md` → `notification`.

- `NotificationsController` lives at the app shell, not on the screen: the badge
  must be right on every tab and the announcer must see an event arrive whatever
  the user is looking at.
- The **first** feed seeds silently — opening the app must never replay a week
  of events as a stack of toasts.
- While the app is open, an arrival is a toast **except** a driver-cancelled
  trip, which is a blocking dialog (`barrierDismissible: false` + `PopScope`).
  That exception only stays justifiable while it stays the only one.

## Map picker (خرائط — swappable provider)
- The location picker uses **free OpenStreetMap** tiles via `flutter_map`, but the
  map library is **isolated behind one widget** so the provider can be swapped
  later (e.g. to Google) with a contained change.
- **Single source of truth:** the app depends only on `LocationPoint`
  ({lat,lng,label}) + `AppMapPicker` (choose a point) / `AppMapView` (read-only,
  with a hand-off to the device's navigation app), all in
  `/packages/shared/lib/map`.
- **Containment rule:** `flutter_map` + `latlong2` are imported **only** in
  `map/app_map_picker.dart` — which is why `AppMapView` lives in that same file
  rather than one of its own; `geolocator` **only** in
  `map/geolocator_location_service.dart` (behind the `LocationService`
  interface); `url_launcher` **only** in `contact/url_link_launcher.dart`
  (behind `LinkLauncher`). Reverse geocoding is behind `ReverseGeocoder`
  (Nominatim impl). **Nothing else in the codebase imports a map/GPS/launcher
  package.**
- A `LinkLauncher` behind an interface is what lets a widget test assert **which
  URL a tap produced** (`tel:+964…`, `https://wa.me/964…` with no `+`) instead
  of mocking a platform channel. Those URLs fail silently on a real phone and
  nowhere else, so they are pinned by tests.
- Reverse geocoding fails often (offline, rate-limited, unnamed road). A missing
  label is a **normal state**: `AppMapView.displayLabel` falls back to
  coordinates, never to a blank line.
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

## `departNow` is LIVE, not "already gone" (locked rule)

**A «الآن» trip is posted with `departureTime = now`, so any hand-written
`departureTime > now` is false the instant it exists.** That single expression is
why `trip-window.ts` was created — and it then came back in three more places,
where it cost riders money:

- `isBookingUpcoming` filed a booking on a trip *search was still offering* under
  «سابقة» before the tap finished.
- From there the app's `canCancel` (which requires `upcoming`) drew **no cancel
  button**, `canContact` hid the driver's number, and `hasLiveBookings` was false
  so حجوزاتي **stopped polling** — which is why a second booking appeared in
  neither tab.
- `BookingService.cancel`'s cutoff was `departureTime − 15min`, already expired
  when the row was created, so even calling the API directly answered
  «فات وقت الإلغاء المجاني». **The seats were held with no way out.**
- `cancel`'s reopen check left a full departNow trip `LOCKED` for the rest of its
  window, so a freed seat was never re-offered and the driver carried an empty
  place.

**Never write the clock out by hand. Ask `catchableUntil` / `isCatchable`.** The
bucket takes `departNow` as a *required* field for exactly this reason — the
type system now refuses a caller who has not thought about it, which is what
caught the old unit spec that had silently tested scheduled trips only.

The cancel/edit deadline is `catchableUntil(trip) − 15min`: unchanged for a
scheduled trip (departure − 15min), and a real 15-minute window for «الآن».

> Known boundary, deliberately not widened: once a departNow window shuts the
> trip goes `LOCKED` and the booking becomes past, so a rider whose driver never
> started can no longer cancel. Releasing that seat is then the driver's action
> (cancel / no-show).

## One booking per rider per trip (locked decision)

**A rider may NOT book the same trip twice.** Two rows for one journey is not a
concept the product has — a rider travelling with family books N seats in one
booking, which is what `WOMEN_FAMILY` already contemplates. Concretely it:

- **defeated the 4-seat cap**: `@Max(4)` is per booking, so 4 + 4 put 8 seats
  behind one rider — measured, not theorised;
- gave the driver two entries for one passenger group at one pickup point;
- forced a special case into rating (`_markRated` already had to mark "every
  booking on the SAME trip"), which is the smell that duplicates were never
  modelled.

It is refused with «لديك حجز على هذه الرحلة بالفعل. يمكنك تعديل عدد المقاعد بدل
حجز جديد.» The guard runs **inside** the seat transaction, after the row-locking
`updateMany`, which is what makes it race-safe without a new index — and the
rollback is what keeps a refused attempt from eating seats.

**So `PATCH /bookings/:id` (change seat count) is in scope and shipped with it.**
Blocking the duplicate without it would leave riders strictly worse off than the
workaround they invented: cancel-and-rebook risks losing the seats to someone
else on a corridor where a trip fills in minutes. Same deadline as cancelling,
same atomic guard, and it reopens a trip it un-fills.

Bookings that already exist as duplicates stay visible and cancellable — the
block is on creating new ones.

## «قادمة» / «سابقة», and rating (locked rule)

**A booking's bucket is a STATUS question, not a clock question.** It used to be
`departureTime > now`, and a driver completing a trip early left the rider's
finished booking — badge reading «مكتملة» — filed under «قادمة». That is the
same confusion that made departNow trips invisible: *when it was scheduled* vs
*what state it is in*.

- The rule lives in **one place**, `services/api/src/booking/booking-lifecycle.ts`,
  and the apps never re-derive it. `/bookings/mine` sends `upcoming`; the client
  files the card where it is told. Two copies is how it comes back.
- «قادمة» holds only what is still actionable. A terminal booking
  (`COMPLETED`/`CANCELLED`/`NO_SHOW`) or a terminal trip
  (`COMPLETED`/`SETTLED`/`CANCELLED`) is past whatever the clock says; an
  `EN_ROUTE` trip is upcoming even though its departure has passed by
  definition.
- **Both directions of rating must exist.** A driver's `ratingAvg` is exactly
  what riders choose a trip on, so a one-way rating path leaves the trust
  signal dead — and empty stars read as a judgement rather than as missing
  data. `/bookings/mine` carries `driverUserId`, `ratable` and `ratedDriver`
  so the app can offer the action, address it, and stop offering it.
- `ratable` is computed server-side to stay in step with what `POST /ratings`
  will accept. **An action the UI offers and the server refuses is worse than
  no action**, so the two are derived from the same statuses.
- A 409 from `POST /ratings` is **idempotent success** on both sides: the
  rating already exists, which is the state the caller wanted.
- One rate sheet for both directions — `packages/shared/lib/rating/rate_sheet.dart`.
  Only the words differ, so only the words are parameters.

## No-show consequences (locked decision)

**Reputation + an escalating temporary block. Never a fee.** Phase 1 is
cash-only, so there is no stored payment method to charge against — a "no-show
fee" would be a number with no collection behind it. The only lever we actually
hold is access to the platform. The cost being answered is real: a rider who
does not turn up takes a whole seat with no fare, **25% of a four-seat trip**,
and drivers are the hard constraint in this market.

- **The numbers are environment, not code**: `NO_SHOW_BLOCK_THRESHOLD` (3),
  `NO_SHOW_WINDOW_DAYS` (30), `NO_SHOW_BLOCK_DAYS` (7). They are *policy*
  values that the first real month of operation will change; a malformed value
  falls back to the default rather than failing boot. The rule itself is pure —
  `services/api/src/booking/no-show-policy.ts`, no Prisma, no Nest.
- **The block starts from the LAST occurrence, not from the moment of
  counting** — otherwise it renews itself on every check and never ends.
- **`BookingStatus.NO_SHOW` alone cannot carry this** and a `NoShowRecord` row
  is not duplication. The status answers *how this booking ended*; the policy
  needs *when it happened* (a rolling window over `SeatBooking.createdAt` would
  count the booking time, not the absence), *whether it was voided* (an appeal
  needs a row that stays visible and stops counting — neither `COMPLETED` nor
  `CANCELLED` can express that without lying), and *who voided it and why*.
- **The block prevents NEW bookings only.** An existing CONFIRMED booking is
  never cancelled by a block, and stays cancellable and editable. Cancelling it
  as punishment hurts the driver too.
- **Server-side is the gate; the client is a courtesy.**
  `BookingService.book()` refuses with a structured 403 (`code:
  'RIDER_BLOCKED_NO_SHOW'`, `blockedUntil`) **before** the seat transaction —
  same position as the gender check, so it never weakens the inventory
  guarantee. `GET /bookings/eligibility` exists so the rider is told *before*
  filling in a booking form, and it **fails open**: a failed eligibility read
  must never block a rider the server would have allowed.
- **A block always names its end date.** "You are blocked" with no date leaves
  the user nothing to do, which is exactly the state that generates a support
  call.

### It is a SEPARATE signal from `ratingAvg` — never folded in

A rating is a **subjective judgement** by one counterparty about a journey that
**happened**; a no-show is an **objective, countable event** about a journey
that **did not**. Folding it into the average would make two-star mean both
"bad driver" and "missed two trips"; a handful of occurrences would drag the
mean down permanently, turning a 30-day window into a life sentence. And the
mechanisms fight: no-shows have a rolling window and an appeal that *voids* an
occurrence, neither of which ratings have — supporting both would mean
recomputing an average retroactively on every appeal. The audiences differ too:
ratings are public to both sides, the count is shown to the **driver only**.

**Tone: a count, not a label.** The driver sees «لم يحضر ٣ مرات مؤخراً» —
`warning`, never `danger`, and no word like "bad". The driver is not being asked
to refuse the rider, only given the context. Voided records stop counting, so a
successful appeal disappears from the driver's view too.

### The cancel trap this fixed (same problem family as departNow)

The cutoff used to be `catchableUntil(trip) − 15min`. Once a «الآن» window shut,
the trip went `LOCKED` with the driver not yet started — and the rider **could
not cancel a trip that had not left**, then got marked `NO_SHOW` for it. A
penalty for something we prevented them from avoiding.

**A rider may cancel (or change seat count) while the trip is `OPEN`/`LOCKED`,
and not from `EN_ROUTE`** (`CANCELLABLE_BEFORE` in `booking.service.ts`). The
arithmetic is the driver's, not the rider's: cancelling before departure gives
back a **resellable seat**; a trapped rider gives an **empty seat AND** a
no-show. **And the converse: a no-show cannot be recorded before `EN_ROUTE`** —
so the two states never overlap. Marking and recording happen in **one
transaction**; a status without a row (or a row without a status) corrupts the
count later with nothing left to point at it.

## Optional safety features (locked decision)

Rides are 1–2 hours between cities, **shared with strangers** — a different
wager from a short city hop, and trust is this product's competitive wedge.

**Everything here is opt-in and user-initiated.** Nothing is shared
automatically, nothing is on by default, and there is no prompt, badge or
nudge anywhere. A rider who never touches these features must see no friction
at all — which is a NEGATIVE guarantee, so it is asserted rather than assumed
(`apps/rider/test/safety_test.dart`).

### «شارك رحلتي» goes out through WhatsApp, not in-app

**Because the recipient does not have the app, and never will** — it is a
mother, a brother, a friend. Any in-app channel reaches only existing users,
which excludes almost everyone a rider actually wants to tell. WhatsApp is
where Iraqi families already are, works on wifi with no balance, and the
rider picks the recipient **in WhatsApp's own picker**: the link is
`https://wa.me/?text=…` with **no number**, so no code path can send it to
someone they did not choose.

- **The message is previewed before it is sent.** This is a safety feature, so
  the rider has to see exactly what leaves their phone. Composing a message
  about where they are and who they are with and firing it on one tap is the
  opposite of the trust it exists for. The preview IS the feature.
- **The plate is the payload.** It is what distinguishes this car from another
  white Corolla. It stays in **Western digits, exactly as registered** — an
  identifier matched against a metal plate, same class as a phone number and a
  coordinate. Iraqi plates are stamped in Western digits.
- **Search does not carry the plate**; `POST /bookings` and `/bookings/mine`
  do. Same reasoning as phone numbers: otherwise scrolling results hands
  anyone every driver's plate.
- **The ٠-dot hazard applies where no golden can see it.** WhatsApp renders
  this text, on a device we do not control, in a font we did not choose. So
  the message never puts a dot-like glyph next to an Arabic-Indic digit **and
  never a `:` immediately before one** — fields are joined with strong Arabic
  words («الساعة», «يوم», «من … إلى») and each sits on its own line. `٠٧:٣٠` is
  safe: that colon is between two digit runs. Cities join with «إلى», never an
  arrow.
- **Nothing is stored.** No recipient, no share log. "Who a rider told about
  their trip" is sensitive data with no Phase 1 use.

### The emergency contact is the rider's own, and never leaves them

Optional name + phone on `User`, set from Settings → الأمان. `null` for almost
everyone, which is the designed default.

- **«اتصال طارئ» requires BOTH a saved contact AND an `EN_ROUTE` trip.**
  Otherwise nothing renders — not a disabled button, not an empty state, not
  an invitation. And it is a STATUS question, never the clock: a «الآن» trip's
  `departureTime` passes the instant it is posted.
- **Solid `danger`** — the loudest control in the design system — is right
  here and nowhere else, precisely because it is never ambient. Under stress,
  one-tap findability beats visual restraint.
- **No confirm dialog.** `tel:` opens the DIALER; it does not place the call.
  The platform already owns that confirmation, and a dialog on top costs
  seconds in the only situation the button exists for.
- **Name AND phone, always together.** A bare number on a screen opened under
  pressure is not something anyone can act on.
- **It is returned by `GET /auth/me` and nothing else.** Every path uses an
  explicit `select` today, but one future `include: { rider: true }` would
  attach the whole row with no unit test failing — so
  `emergency-contact.int-spec.ts` **serialises the real driver-facing payloads
  and searches the text** for the number.

### The public trip-status page: deliberately NOT built

A forwarded WhatsApp link is a **permanent unauthenticated handle** to a trip —
anyone in any group it reaches can watch it. Bounding that needs token
issuance, rotation and expiry, which is not cheap. The only web surface we have
is the admin panel, and making part of it public inverts its threat model.
And the payoff is small: the rider is *in the car* and can send another
message. The WhatsApp message alone is the value, and it ships.

## Splitting work into several PRs (locked rule)

**Every PR targets `main` directly, and they are merged in order. Never stack a
PR on another PR's branch.**

A stacked PR does *not* get retargeted to `main` when its parent merges — GitHub
only does that when the base branch is **deleted** on merge. Leave the branches
in place and each PR merges into its stack parent instead, exactly as
configured and silently: every PR goes green, every PR reports "Merged", and
`main` receives only the bottom one. It cost a full recovery cycle here — three
changes sat merged-but-unshipped in a side branch while everything looked done.

- Target `main` from the start. Until its predecessor lands, a PR's diff shows
  the predecessor's commits too; that resolves as each one merges, and is a far
  smaller cost than the failure above.
- **Verify against `main`, never against PR state.** "Merged" answers a question
  about the PR, not about `main`:
  ```sh
  git fetch origin main
  git merge-base --is-ancestor <commit> origin/main && echo ON MAIN || echo MISSING
  ```
- Split along real dependencies. If the later work textually modifies files the
  earlier work created, that ordering is in the code — merging out of order is
  not an option the split can grant. Check with
  `git diff --name-only A^ B` per group and intersect.
- The payoff is revertability: one merge commit per change on `main`, so
  `git revert -m 1 <merge>` drops exactly one of them.

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
