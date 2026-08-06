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
- **Known, unfixed:** `Poller._inFlight` is a latch, so an `onPoll` future that
  never completes silences that scope for the life of the screen while
  `isTicking` still reports true. Dio's timeouts are applied in the adapter —
  after the interceptor chain — so the `tokenStore.read()` await in `ApiClient`
  sits outside that budget. A watchdog is the fix but it trades against "polls
  never stack", so it wants its own change and its own test.
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
| driver — تفاصيل الرحلة | **20s** | `OPEN` / `LOCKED` / `EN_ROUTE` |
| both — notification badge | **30s** | authenticated (app-shell wide, so a cancellation reaches the user on *any* screen) |

Every list screen (both apps) has pull-to-refresh regardless of whether it polls.

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
