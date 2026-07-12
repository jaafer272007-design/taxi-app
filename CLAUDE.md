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
/packages/shared   أنواع/ثوابت مشتركة
/docs              PROJECT_PLAN.md, PHASE1_BUILD_BRIEF.md
```

## ثوابت غير قابلة للتفاوض
- العملة **IQD** (أعداد صحيحة، بلا كسور).  التوقيت **Asia/Baghdad**.  الواجهة **عربي RTL**.
- الهوية = رقم موبايل **+964** عبر **WhatsApp OTP** (لا SMS).
- **مخزون المقاعد transactional** دائماً (row-lock أو `UPDATE ... WHERE seatsAvailable >= seatCount`) — منع overbooking شرط أساسي.
- احترم آلات الحالة بـ `PHASE1_BUILD_BRIEF.md` §3؛ لا تسمح بانتقالات خارجها.

## اصطلاحات
- حدود modules واضحة؛ منطق الأعمال بالـ services لا بالـ controllers.
- معالجة أخطاء موحّدة + رسائل عربية للمستخدم.
- كل endpoint يرجع أخطاء واضحة (مقعد غير متاح، سائق غير مُعتمد، إلخ).
- تعليقات/أسماء إنكليزي بالكود؛ نصوص المستخدم عربي.

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

# ملحق: تفعيل الـ Skills تلقائياً (Skill auto-activation)

> قسم مستقل يخص توجيه الـ 20 skill المنصّبة (تسويق/تصميم/ملفات). لا علاقة له بحواجز Phase 1 أعلاه — احترم تلك الحواجز دائماً.

## Skill auto-activation

**Purpose of this section:** the user has 20 skills installed and wants them used
**proactively**. When a request matches the triggers below, invoke the skill on
your own — **do not** wait for the user to name it, and don't ask "should I use
skill X?" first. Just use it and mention which skill you're applying.

**How triggering actually works (two levers):**
1. **In this repo / Claude Code sessions** → *this file* is the source of truth.
   The routing table below is loaded every session and governs which skill fires.
2. **In claude.ai chats** → the skill's own **description** governs triggering.
   All 20 descriptions were audited and are already specific (none is vague), so
   no source edit is required. Optional tightened versions are listed under
   [Optional source-description tweaks](#optional-source-description-tweaks) if
   you ever want to paste them into *claude.ai › Settings › Capabilities › Skills*.

**Audit result:** 20/20 descriptions rated *already-specific*; **0** need a source
edit. No true duplicate skills were found — the overlaps below are handled by the
disambiguation rules, not by deleting a skill.

---

### Routing table

Legend: **Fire when** = request patterns (phrased for this taxi app) that should
auto-activate the skill · **Don't fire when** = to avoid false positives.

#### Code / product design

| Skill | Fire when | Don't fire when |
|---|---|---|
| **ui-ux-pro-max** | Build/design/review/refactor any UI: driver signup & onboarding screens, ride-booking screen, rider home/map, fare-estimate card, trip-summary modal, driver-earnings dashboard, bottom navbar / ride-status sheet, dark mode & palettes, in-app charts. Stacks: React, Next.js, Vue, Svelte, SwiftUI, React Native, Flutter, Tailwind, shadcn/ui, HTML/CSS. | Pure backend, API, pricing-algorithm, data-model, or marketing work with no interface component. |

#### Writing polish

| Skill | Fire when | Don't fire when |
|---|---|---|
| **stop-slop** | Any human-facing prose is being drafted/edited/reviewed: app-store description, push/email copy, landing-page copy, blog/social posts, in-app announcements. Also "make this sound less AI-generated." Runs as a **finishing pass** over any copy another skill produced. | Code, UI/component work, config, or data output. |

#### Marketing — strategy

| Skill | Fire when | Don't fire when |
|---|---|---|
| **marketing-ideas** | **Last resort only** (user preference): a purely open-ended "I'm totally stuck, just throw ideas at me" ask with no discernible angle. If *any* more specific skill fits (marketing-plan, content-strategy, marketing-psychology, or a channel skill), use that **instead**. | Any request that maps to a more specific skill — always prefer the specific one over marketing-ideas. |
| **marketing-plan** | A comprehensive deliverable: "marketing plan," "growth plan," "GTM / go-to-market," "AARRR plan," "90-day plan," "12-month roadmap," "fractional CMO plan," "how to spend our budget to grow." Produces a 13-section AARRR plan tied to budget/team/stage. | A loose brainstorm (→ marketing-ideas) or a single narrow channel/stage. |
| **marketing-psychology** | A behavioral lever is named or implied: anchoring, social proof, scarcity/urgency, loss aversion, framing, nudge, "why do riders drop off," "what makes them complete a booking." | Optimizing one specific page/funnel (→ cro*), setting actual prices (→ pricing*), or wording copy (→ copywriting*). |
| **content-strategy** | Deciding *what* content to make: "what should we blog about," content pillars, topic clusters, editorial calendar, content roadmap for a city launch. | Writing the actual piece (→ copywriting*), SEO/keyword audit (→ seo-audit*), or social scheduling (→ social*). |

#### Marketing — channels

| Skill | Fire when | Don't fire when |
|---|---|---|
| **community-marketing** | Owned communities & advocacy: rider/driver Discord or Slack, subreddit/forum, ambassador / brand-advocate program, word-of-mouth engine, community-led growth. | Paid ads, in-app referral-code mechanics, or email/push lifecycle. |
| **co-marketing** | Partnering with *another brand*: "who should we partner with," joint campaign, cross-promotion, co-brand, integration marketing (e.g. hotels/restaurants/airlines bundling rides). | Rider invite-a-friend referrals (→ referrals*), launch-day announcements (→ launch*). |
| **cold-email** | B2B outbound: prospecting emails + follow-up sequences to corporates, fleet owners, hotels, event organizers; "nobody's replying to my outreach." | Rider/driver lifecycle or transactional emails (receipts, confirmations, win-back) — those are warm/lifecycle emails. |
| **ai-seo** | Get surfaced/cited by AI answer engines: AEO, GEO, LLMO, "show up in ChatGPT/Perplexity," AI Overviews, AI citations, `llms.txt`, "rank in AI search for book a taxi in <city>." | Traditional keyword/backlink SEO (→ seo-audit*) or JSON-LD/structured data (→ schema*). |

#### Marketing — creative

| Skill | Fire when | Don't fire when |
|---|---|---|
| **image** | Organic marketing **visuals**: blog heroes, social graphics, product/app mockups, banners, OG images, brand assets; tools Flux/Midjourney/DALL-E/Ideogram; WebP/image optimization. | Paid **ad copy** (→ ad-creative), video (→ video), or buildable product UI (→ ui-ux-pro-max). |
| **video** | Anything with **motion**: explainer/product-demo/promo videos, AI avatar / talking head; Remotion/Veo/Sora/Runway/HeyGen/Pika; "make me a video." | Static graphics (→ image), content strategy/scripting (→ social*), paid video *ad copy* (→ ad-creative). |
| **ad-creative** | Paid-ad **copy/text**: headlines, primary text, RSA headlines, bulk ad variations, creative testing for Facebook/Google/LinkedIn. | Campaign budgeting/targeting (→ ads*), landing-page/in-app copy (→ copywriting*), the ad's *visual* (→ image), the *footage* (→ video). |

#### Marketing — ops / measurement

| Skill | Fire when | Don't fire when |
|---|---|---|
| **analytics** | Tracking & measurement setup: event/conversion tracking, GA4, GTM, UTM, tracking plan, attribution, Mixpanel/Segment, "why aren't my `ride_requested`/`driver_accepted` events firing," "how do I measure X." | Experiment design (→ ab-testing), or charting already-collected data (→ dataviz built-in). |
| **ab-testing** | Experiments: A/B or split test, variant copy, multivariate, hypothesis, "which version converts better," statistical significance, ICE-scored experiment backlog. | Plain event/funnel tracking (→ analytics), single-page conversion tweaks with no experiment (→ cro*). |

#### Documents (fire when the deliverable IS that file type)

| Skill | Fire when | Don't fire when |
|---|---|---|
| **xlsx** | A **spreadsheet** is the input/output: `.xlsx/.xlsm/.csv/.tsv` — weekly rides/fares report, driver-payout sheet, dedupe a signups CSV, formula columns, pivots, CSV→Excel. | Tabular data staying in-app (DB tables, API JSON, dashboard charts) with no spreadsheet file. |
| **pptx** | A **deck/presentation** `.pptx/.potx`: investor pitch deck, growth-metrics deck, board presentation, speaker notes, extract/merge slides. | Word/PDF reports, Google Slides, in-app UI. |
| **pdf** | A **PDF**: ride receipts, driver earnings statements, trip invoices, insurance/inspection form-fill, OCR a scanned doc, merge/split/watermark. | In-app HTML receipts, CSV/Excel exports, image-only assets. |
| **docx** | A **Word** doc `.docx/.dotx`: driver-onboarding policy, investor report (narrative), partnership-agreement letter, incident-report template, tracked changes/comments. | PDFs, spreadsheets, Google Docs, plain-text/Markdown, in-app copy. |

#### Meta

| Skill | Fire when | Don't fire when |
|---|---|---|
| **skill-creator** | Authoring/tuning a **skill itself**: create a new skill, edit/optimize an existing one, run evals, benchmark, "my skill isn't auto-firing, fix its triggering." | Ordinary app feature, UI, or marketing-content work. |

> `*` = a sibling skill referenced by a description but **not currently installed**
> (cro, pricing, copywriting, referrals, launch, seo-audit, schema, social, ads,
> emails, product-marketing, sales-enablement, onboarding, signup). `dataviz` is a
> built-in Claude Code skill. If a request lands squarely on one of these, say so
> and use the closest installed skill or handle it directly.

---

### Disambiguation — when two skills overlap

Most overlaps are **compose** relationships (chain them, don't choose). A few are
**genuine forks** (pick by the rule). None require deleting a skill.

**Compose (use both, in order):**
- **image + ad-creative** → a "Facebook ad" = `image` makes the visual/banner **and** `ad-creative` writes the headlines/primary text. A bare "make the ad creative" needs both.
- **ad-creative + stop-slop** → generate ad copy with `ad-creative`, then run `stop-slop` to strip AI tells.
- **co-marketing + cold-email** → `co-marketing` picks the partner & structures the deal; `cold-email` writes the outbound sequence to pitch them.
- **video + ad-creative** → `video` produces the footage; `ad-creative` writes the ad's text.
- **ui-ux-pro-max + ab-testing** → `ui-ux-pro-max` builds the screen variants; `ab-testing` designs the experiment.
- **ui-ux-pro-max + dataviz** → `dataviz` picks chart type/encoding/palette; `ui-ux-pro-max` lays it out in the app screen.
- **analytics + ab-testing** → `analytics` instruments the events; `ab-testing` designs the experiment that reads them.

**Fork (pick one by the rule):**

> **Global rule (user preference):** always prefer the more **specific** skill.
> `marketing-ideas` is a fallback used *only* when no specific strategy or channel
> skill fits the request.

- **marketing-ideas vs marketing-plan** → default to `marketing-plan` for any real growth/plan/strategy ask; use `marketing-ideas` only for a pure "just brainstorm, no structure" request.
- **marketing-ideas vs content-strategy** → any content-planning angle (topics, pillars, calendar) → `content-strategy`; `marketing-ideas` only if it's not about content at all and no other skill fits.
- **marketing-ideas vs marketing-psychology** → any behavioral/persuasion angle (nudge, loss aversion, social proof, "why do riders drop off") → `marketing-psychology`; `marketing-ideas` only as last resort.
- **marketing-plan vs content-strategy** → whole-funnel plan → `marketing-plan`; content-only editorial roadmap → `content-strategy`.
- **content-strategy vs ai-seo** → choosing topics/calendar → `content-strategy`; optimizing content to be cited by LLMs → `ai-seo`.
- **community-marketing vs co-marketing** → your own rider/driver community & advocates → `community-marketing`; cross-promo with an outside brand → `co-marketing`.
- **image vs ui-ux-pro-max** → static app-store/marketing mockup image → `image`; buildable product UI code → `ui-ux-pro-max`.
- **image vs video** → static graphic → `image`; anything with motion → `video`.
- **xlsx vs pdf vs docx** (report/export) → decide by the output-format word: editable numbers → `xlsx`; narrative Word doc → `docx`; final printable statement/receipt → `pdf`. **If no format is named, ask which one.**

---

### Optional source-description tweaks

None are required (all 20 descriptions are already specific). If you want to make
claude.ai triggering marginally sharper, the thinnest description is **stop-slop**;
a tightened version:

> *Remove AI writing patterns, clichés, and predictable tells from human-facing
> prose. Use when drafting, editing, or reviewing any copy — marketing pages, app
> store listings, push/email notifications, blog and social posts, onboarding and
> in-app text — so it reads as naturally human-written. Not for code, UI, or config.*

Paste into *claude.ai › Settings › Capabilities › Skills → stop-slop → Edit* if desired.
