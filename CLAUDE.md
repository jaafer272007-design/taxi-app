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
