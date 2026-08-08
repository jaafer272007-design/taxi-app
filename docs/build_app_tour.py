#!/usr/bin/env python3
"""Build docs/APP_TOUR.html — a single self-contained, shareable tour of the app.

Every image is a committed golden screenshot from docs/ui-screenshots/, embedded
as a data URI so the file can be sent as one attachment and opened on a phone
with no network. Nothing here regenerates or edits a screenshot; if a screen
looks wrong in the tour, fix the golden, not this script.

    python3 docs/build_app_tour.py          # writes docs/APP_TOUR.html
    node docs/print_app_tour.mjs            # then writes docs/APP_TOUR.pdf

The caption for each screen describes what a CUSTOMER sees and does there, not
how it is built.
"""
import base64
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "ui-screenshots"
FONTS = ROOT / "packages" / "shared" / "assets" / "fonts"
OUT = ROOT / "docs" / "APP_TOUR.html"


def data_uri(path: pathlib.Path, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


def shot(name: str) -> str:
    p = SHOTS / f"{name}.png"
    if not p.exists():
        sys.exit(f"missing screenshot: {p}")
    return data_uri(p, "image/png")


def font(name: str) -> str:
    return data_uri(FONTS / name, "font/ttf")


# ── The tour ────────────────────────────────────────────────────────────────
# (file stem, title, caption). Order is the journey, not the filename.

RIDER = [
    ("onboarding_phone_light", "تسجيل الدخول",
     "يدخل الراكب رقم موبايله فقط — بلا كلمة مرور. يصله رمز التحقق عبر واتساب."),
    ("onboarding_otp_light", "رمز التحقق",
     "يكتب الراكب الرمز الذي وصله على واتساب، فيدخل مباشرة إلى التطبيق."),
    ("rider_profile_light", "الاسم والجنس",
     "الاسم يظهر للسائق عند الحجز. الجنس يُستخدم لتحديد أهلية الرحلات النسائية والعائلية."),
    ("search_light", "البحث عن رحلة",
     "يختار الراكب مدينة الانطلاق والوصول والوقت. ويستطيع تحديد نوع الرحلة "
     "(عامة أو نسائية-عائلية) وجنس السائق."),
    ("results_light", "نتائج البحث",
     "كل رحلة متاحة أمامه: وقت الانطلاق، اسم السائق وتقييمه، نوع السيارة ولونها، "
     "سعر المقعد، وعدد المقاعد الفارغة. ويرتّبها حسب الأقرب موعداً أو الأرخص."),
    ("booking_light", "حجز مقعد",
     "يختار الراكب عدد المقاعد ويحدّد نقطة انطلاقه ونزوله على الخريطة — من الباب "
     "إلى الباب — ويرى المبلغ الإجمالي قبل التأكيد. الدفع نقداً عند الرحلة."),
    ("booking_confirmation_light", "تم تأكيد الحجز",
     "تظهر تفاصيل الحجز كاملة مع رقم السائق، وزرَّي الاتصال والواتساب للتواصل معه مباشرة."),
    ("my_bookings_light", "حجوزاتي — القادمة",
     "يتابع الراكب حجزه القادم: وقته، نقطتاه، والمبلغ. ويستطيع الاتصال بالسائق "
     "أو إلغاء الحجز."),
    ("my_bookings_past_light", "حجوزاتي — السابقة",
     "سجل الرحلات المنتهية. ومن هنا يقيّم الراكب سائقه، وهذا التقييم هو ما يظهر "
     "لبقية الركّاب عند اختيارهم."),
    ("notifications_light", "الإشعارات",
     "كل ما يخص رحلاته في مكان واحد: تأكيد الحجز، انطلاق السائق، انتهاء الرحلة، "
     "أو إلغاؤها من السائق."),
    ("settings_light", "الإعدادات",
     "يعدّل الراكب اسمه، ويختار مظهر التطبيق (فاتح أو داكن أو حسب إعداد الهاتف)، "
     "ويسجّل الخروج."),
]

DRIVER = [
    ("become_driver_light", "كن سائقاً",
     "يبدأ السائق من هنا: يعلن رحلته بين المحافظات، يستقبل حجوزات الركّاب، "
     "ويستلم الأجرة نقداً."),
    ("vehicle_form_light", "بيانات المركبة",
     "يدخل السائق نوع سيارته وموديلها ورقم لوحتها ولونها وعدد مقاعدها. "
     "تظهر هذه البيانات للركّاب عند الحجز."),
    ("documents_light", "المستمسكات",
     "يرفع السائق الهوية وإجازة السوق وتسجيل المركبة، ويتابع حالة كل مستند."),
    ("pending_review_light", "حالة الطلب",
     "بعد الرفع تراجع الإدارة مستمسكاته. لا يستطيع نشر رحلات حتى يُعتمد حسابه، "
     "ويصله إشعار فور الاعتماد."),
    ("post_trip_light", "نشر رحلة",
     "يحدّد السائق المسار ونوع الرحلة، ووقتها — «الآن» أو مجدولة — وعدد المقاعد "
     "التي يعرضها، وسعر المقعد ضمن المدى المسموح على ذلك المسار."),
    ("my_trips_light", "رحلاتي",
     "كل رحلاته وحالة كل واحدة: مفتوحة للحجز، أو مكتملة الحجز، أو جارية — "
     "مع عدد المقاعد المتبقية في كل رحلة."),
    ("trip_detail_light", "تفاصيل الرحلة",
     "يرى السائق ركّاب رحلته، ونقطة انطلاق ونزول كل راكب، ورقمه للتواصل. "
     "ومن هنا يبدأ الرحلة."),
    ("trip_detail_enroute_light", "الرحلة جارية",
     "أثناء الرحلة يؤشّر السائق مَن صعد ومَن لم يحضر، ويرى أمامه المبلغ المطلوب تحصيله."),
    ("trip_completed_light", "اكتملت الرحلة",
     "ملخّص بعد الانتهاء: عدد الركّاب، والمقاعد التي رَكِبت، والمبلغ المحصّل نقداً."),
    ("earnings_light", "أرباحي",
     "أرباح اليوم والإجمالي منذ البداية، مع سجل مفصّل لكل مبلغ. "
     "كل المبالغ نقدية تُحصَّل من الركّاب مباشرة — التطبيق لا يحتفظ بأي مبلغ."),
]

ADMIN = [
    ("admin_corridors_light", "الممرات والتسعير",
     "تُدير الإدارة المسارات بين المدن، وتحدّد لكل مسار السعر المقترح والحد الأدنى "
     "والأعلى الذي يستطيع السائق اختياره ضمنه."),
    ("admin_corridor_form_light", "تعديل ممر",
     "تعديل أسعار المسار، أو إيقافه وتفعيله للحجز والنشر."),
]

DARK = [
    ("results_dark", "نتائج البحث"),
    ("booking_confirmation_dark", "تأكيد الحجز"),
    ("my_bookings_dark", "حجوزاتي"),
    ("my_trips_dark", "رحلاتي — السائق"),
    ("trip_detail_dark", "تفاصيل الرحلة — السائق"),
    ("earnings_dark", "أرباحي — السائق"),
]


def phone_card(stem: str, title: str, caption: str) -> str:
    return f"""      <figure class="card">
        <div class="phone"><img src="{shot(stem)}" alt="{title}" loading="lazy"></div>
        <figcaption><h3>{title}</h3><p>{caption}</p></figcaption>
      </figure>"""


def wide_card(stem: str, title: str, caption: str) -> str:
    return f"""      <figure class="card wide">
        <div class="screen"><img src="{shot(stem)}" alt="{title}" loading="lazy"></div>
        <figcaption><h3>{title}</h3><p>{caption}</p></figcaption>
      </figure>"""


def dark_card(stem: str, title: str) -> str:
    return f"""      <figure class="card small">
        <div class="phone"><img src="{shot(stem)}" alt="{title}" loading="lazy"></div>
        <figcaption><h3>{title}</h3></figcaption>
      </figure>"""


def build() -> str:
    rider = "\n".join(phone_card(*s) for s in RIDER)
    driver = "\n".join(phone_card(*s) for s in DRIVER)
    admin = "\n".join(wide_card(*s) for s in ADMIN)
    dark = "\n".join(dark_card(*s) for s in DARK)

    return f"""<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>تكسي مشترك — جولة في التطبيق</title>
<style>
  @font-face {{
    font-family: 'Cairo'; font-weight: 400; font-display: block;
    src: url({font('Cairo-Regular.ttf')}) format('truetype');
  }}
  @font-face {{
    font-family: 'Cairo'; font-weight: 700; font-display: block;
    src: url({font('Cairo-Bold.ttf')}) format('truetype');
  }}

  /* The Masar palette, same tokens the apps ship with. */
  :root {{
    --pine: #0E5C4A;
    --paper: #F4F1EA;
    --surface: #FFFFFF;
    --ink: #16201C;
    --muted: #5C6660;
    --line: #E3DED2;
    --saffron: #DE8F27;
  }}

  * {{ box-sizing: border-box; }}
  html {{ -webkit-text-size-adjust: 100%; }}
  body {{
    margin: 0; background: var(--paper); color: var(--ink);
    font-family: 'Cairo', system-ui, sans-serif; line-height: 1.7;
  }}

  .wrap {{ max-width: 1000px; margin: 0 auto; padding: 0 20px 64px; }}

  /* ── Cover ─────────────────────────────────────────────────────────── */
  .cover {{
    background: var(--pine); color: #fff; padding: 56px 32px 48px;
    text-align: center; margin-bottom: 40px;
  }}
  .cover h1 {{ margin: 0 0 8px; font-size: 34px; font-weight: 700; }}
  .cover .sub {{ margin: 0 auto; max-width: 34em; opacity: .92; font-size: 17px; }}
  .cover .meta {{ margin-top: 22px; font-size: 14px; opacity: .75; }}

  .lead {{
    background: var(--surface); border: 1px solid var(--line); border-radius: 16px;
    padding: 20px 24px; margin: 0 0 40px; font-size: 16px;
  }}
  .lead p {{ margin: 0 0 10px; }}
  .lead p:last-child {{ margin-bottom: 0; }}
  .lead strong {{ color: var(--pine); }}

  /* ── Sections ──────────────────────────────────────────────────────── */
  section {{ margin-bottom: 8px; }}
  .sec-head {{
    display: flex; align-items: baseline; gap: 12px;
    border-bottom: 3px solid var(--pine); padding-bottom: 10px; margin: 40px 0 8px;
  }}
  .sec-head h2 {{ margin: 0; font-size: 25px; color: var(--pine); font-weight: 700; }}
  .sec-head .note {{ color: var(--muted); font-size: 15px; }}
  .sec-intro {{ color: var(--muted); margin: 0 0 24px; font-size: 15px; }}

  .grid {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 28px; }}
  .grid.thumbs {{ grid-template-columns: repeat(3, 1fr); gap: 20px; }}
  .grid.one {{ grid-template-columns: 1fr; }}

  .card {{ margin: 0; break-inside: avoid; page-break-inside: avoid; }}
  .card .phone {{
    /* A light bezel so a screenshot reads as a phone, not a floating rectangle. */
    background: var(--surface); border: 1px solid var(--line);
    border-radius: 22px; padding: 8px; overflow: hidden;
  }}
  .card .screen {{
    background: var(--surface); border: 1px solid var(--line);
    border-radius: 12px; padding: 6px; overflow: hidden;
  }}
  .card img {{ display: block; width: 100%; height: auto; border-radius: 14px; }}
  .card .screen img {{ border-radius: 8px; }}
  .card figcaption {{ padding: 12px 4px 0; }}
  .card h3 {{
    margin: 0 0 4px; font-size: 17px; font-weight: 700; color: var(--pine);
  }}
  .card p {{ margin: 0; font-size: 14.5px; color: var(--muted); }}
  .card.small h3 {{ font-size: 15px; }}

  .footnote {{
    margin-top: 48px; border-top: 1px solid var(--line); padding-top: 16px;
    color: var(--muted); font-size: 13.5px;
  }}

  /* ── Phone screens: one column, bigger images ──────────────────────────
     `screen and` is load-bearing: Chromium lays a PDF page out at the page-box
     width (A4 minus margins ≈ 703px), which is under this breakpoint — so an
     unscoped rule would silently collapse the PDF to one screenshot per page
     and double its length. */
  @media screen and (max-width: 720px) {{
    .grid, .grid.thumbs {{ grid-template-columns: 1fr; }}
    .cover {{ padding: 40px 20px 34px; }}
    .cover h1 {{ font-size: 27px; }}
  }}

  /* ── Print / PDF ───────────────────────────────────────────────────── */
  @page {{ size: A4; margin: 14mm 12mm; }}
  @media print {{
    body {{ background: #fff; }}
    .wrap {{ max-width: none; padding: 0; }}
    .cover {{ margin-bottom: 24px; }}
    .sec-head {{ break-after: avoid; page-break-after: avoid; }}
    .grid {{ gap: 18px; }}
    .card p {{ font-size: 12.5px; }}
    .card h3 {{ font-size: 15px; }}
  }}
</style>
</head>
<body>

<header class="cover">
  <h1>تكسي مشترك</h1>
  <p class="sub">منصّة نقل مشترك بالمقعد بين المحافظات — جولة في شاشات التطبيق</p>
  <p class="meta">تطبيق الراكب · تطبيق السائق · لوحة تحكم الإدارة</p>
</header>

<div class="wrap">

  <div class="lead">
    <p>هذه جولة في شاشات التطبيق كما هي اليوم. الفكرة باختصار:
    <strong>السائق يعلن رحلته ومقاعدها وسعرها، والراكب يحجز مقعداً واحداً أو أكثر
    في تلك الرحلة</strong> — من الباب إلى الباب، والدفع نقداً عند الرحلة.</p>
    <p>التطبيق عربي بالكامل ومن اليمين إلى اليسار، والأرقام والعملة بالدينار العراقي.
    الدخول برقم الموبايل عبر واتساب، بلا كلمة مرور.</p>
  </div>

  <section>
    <div class="sec-head">
      <h2>تطبيق الراكب</h2><span class="note">من التسجيل إلى نهاية الرحلة</span>
    </div>
    <p class="sec-intro">رحلة الراكب: يسجّل دخوله، يبحث عن رحلة، يحجز مقعده،
    يتابع حجزه ويتواصل مع السائق، ثم يقيّمه بعد الوصول.</p>
    <div class="grid">
{rider}
    </div>
  </section>

  <section>
    <div class="sec-head">
      <h2>تطبيق السائق</h2><span class="note">من الاعتماد إلى تحصيل الأجرة</span>
    </div>
    <p class="sec-intro">رحلة السائق: يسجّل مركبته ومستمسكاته وينتظر اعتماد
    الإدارة، ثم ينشر رحلاته ويستقبل الحجوزات ويحصّل الأجرة نقداً.</p>
    <div class="grid">
{driver}
    </div>
  </section>

  <section>
    <div class="sec-head">
      <h2>لوحة تحكم الإدارة</h2><span class="note">على المتصفح</span>
    </div>
    <p class="sec-intro">تعمل على الحاسوب. منها تُدار المسارات وأسعارها،
    ويُعتمد السائقون الجدد.</p>
    <div class="grid one">
{admin}
    </div>
  </section>

  <section>
    <div class="sec-head">
      <h2>الوضع الداكن</h2><span class="note">نماذج مختارة</span>
    </div>
    <p class="sec-intro">كل شاشة في التطبيقين لها مظهر فاتح ومظهر داكن،
    ويتبع التطبيق إعداد الهاتف تلقائياً ما لم يختر المستخدم غير ذلك.</p>
    <div class="grid thumbs">
{dark}
    </div>
  </section>

  <p class="footnote">
    الصور أعلاه لقطات فعلية من شاشات التطبيق بمقاس هاتف ٣٩٠×٨٤٤، ومن لوحة التحكم
    على المتصفح. البيانات الظاهرة فيها بيانات تجريبية للعرض.
  </p>

</div>
</body>
</html>
"""


if __name__ == "__main__":
    OUT.write_text(build(), encoding="utf-8")
    mb = OUT.stat().st_size / 1024 / 1024
    print(f"wrote {OUT.relative_to(ROOT)} ({mb:.1f} MB)")
