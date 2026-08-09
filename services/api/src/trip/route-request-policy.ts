/**
 * طلبات المسارات — السياسة في مكان واحد، بلا Prisma وبلا Nest.
 *
 * ## المشكلة التي تجيب عنها
 *
 * عندنا ٣٠٦ ممرات، والسائقون يعلنون على حفنة منها. الراكب الذي يبحث في مسار
 * بلا عرض يرى حالة فارغة صحيحة تماماً ثم يغادر — **ونحن ما نتعلّم شيئاً**.
 * كنا نخمّن أي المسارات تستحق استقطاب سائقين، بدل أن يُقال لنا.
 *
 * ## رقمان فقط، وكلاهما سياسة لا هندسة
 *
 * [RouteRequestPolicy.ttlDays] هو **عمر الطلب**: بعده لا يولّد إشعاراً ولا
 * يُحتسب في تجميع اللوحة. سببه مباشر: راكب طلب مساراً في شباط ما يريد رنّة
 * في أيار عن رحلة نسي أنه سألها. والوجه الثاني للسبب أهم — **عدّ الطلبات هو
 * كامل قيمة هذه الميزة**، وعدّ بلا نافذة يتحوّل إلى مجموع تاريخي يكبر أبداً
 * ولا يقول شيئاً عن الطلب *الآن*، وهو السؤال الوحيد الذي يقرّر أين نستقطب
 * سائقاً هذا الأسبوع.
 *
 * يُقرأ من البيئة عمداً، بنفس نمط `no-show-policy.ts`: قيمة فاسدة ترجع
 * للافتراضي بدل أن تُسقط الإقلاع.
 *
 * ## «يوم» بغداد، ولماذا يُحسب هنا لا في قاعدة البيانات
 *
 * قاعدة الـdedupe هي «طلب واحد لكل راكب لكل ممر **في اليوم**»، وهي مفروضة
 * بفهرس فريد على `(riderId, corridorId, requestedDay)`. فمعنى «اليوم» لازم
 * يُحسم قبل الكتابة، لا وقت القراءة.
 *
 * التوقيت **Asia/Baghdad** (ثابت غير قابل للتفاوض في CLAUDE.md)، وهو
 * **UTC+3 على مدار السنة** — العراق ألغى التوقيت الصيفي، فما في التواء
 * موسمي يستدعي مكتبة مناطق زمنية. الإزاحة ثابتة، فالحساب حسبة واحدة
 * قابلة للاختبار بأرقام.
 *
 * الفخّ الذي تتجنّبه: `new Date().toISOString().slice(0, 10)` يعطي يوم **UTC**،
 * فنقرة الساعة ١٠ مساءً بتوقيت بغداد تُنسب لليوم السابق — وراكب ينقر مساءً ثم
 * ينقر بعد منتصف الليل بقليل كان سيصنع صفّين لِما هو ليلة واحدة عنده.
 */

/** الأرقام القابلة للضبط. */
export interface RouteRequestPolicy {
  /**
   * كم يوماً يبقى الطلب حيّاً: يولّد إشعاراً ويُحتسب في تجميع اللوحة.
   */
  ttlDays: number;
}

/**
 * ٣٠ يوماً.
 *
 * مطابق لنافذة عدم الحضور، وليس مصادفة: كلاهما يسأل «ما الذي يجري **هذا
 * الشهر**». وهي أطول بكثير من أي دورة استقطاب سائق (أيام)، فالطلب يبقى
 * مرئياً للأدمن طوال الوقت الذي يمكن فيه التصرّف بناءً عليه، ثم يسقط.
 */
export const DEFAULT_ROUTE_REQUEST_POLICY: RouteRequestPolicy = {
  ttlDays: 30,
};

const DAY_MS = 24 * 60 * 60 * 1000;

/** إزاحة بغداد الثابتة عن UTC. العراق بلا توقيت صيفي منذ ٢٠٠٨. */
const BAGHDAD_OFFSET_MS = 3 * 60 * 60 * 1000;

/**
 * أقدم `createdAt` لا يزال ضمن النافذة.
 *
 * يستعملها **الفان-آوت وتجميع اللوحة معاً**، وهذا هو المقصود: لو اختلفا
 * لظهر للأدمن طلبٌ لن يُشعَر صاحبه أبداً — أو أسوأ، رقمٌ يقرّر استقطاب سائق
 * لمسار ما عاد أحد يريده.
 */
export function outstandingSince(
  policy: RouteRequestPolicy = DEFAULT_ROUTE_REQUEST_POLICY,
  now: Date = new Date(),
): Date {
  return new Date(now.getTime() - policy.ttlDays * DAY_MS);
}

/** هل هذا الطلب لا يزال حيّاً؟ نفس قاعدة {@link outstandingSince}، للصف الواحد. */
export function isWithinTtl(
  createdAt: Date,
  policy: RouteRequestPolicy = DEFAULT_ROUTE_REQUEST_POLICY,
  now: Date = new Date(),
): boolean {
  return createdAt.getTime() > outstandingSince(policy, now).getTime();
}

/**
 * يوم التقويم بتوقيت بغداد الذي تقع فيه [at]، كـ `DATE` (منتصف ليل UTC).
 *
 * منتصف ليل UTC لأن عمود `@db.Date` بلا منطقة زمنية، وPrisma يقرأه ويكتبه
 * كـ`DateTime` عند `00:00:00Z`. القيمة **مفتاح**، لا لحظة: لا تُعرض لأحد ولا
 * تُقارن بساعة.
 */
export function baghdadDayKey(at: Date = new Date()): Date {
  const shifted = at.getTime() + BAGHDAD_OFFSET_MS;
  return new Date(Math.floor(shifted / DAY_MS) * DAY_MS);
}

/** يقرأ السياسة من البيئة، مع الرجوع للافتراضي عند الغياب أو القيمة الفاسدة. */
export function readRouteRequestPolicy(
  get: (key: string) => string | undefined,
): RouteRequestPolicy {
  const raw = get('ROUTE_REQUEST_TTL_DAYS');
  if (raw === undefined || String(raw).trim() === '') {
    return DEFAULT_ROUTE_REQUEST_POLICY;
  }
  const n = Number(raw);
  return {
    ttlDays:
      Number.isFinite(n) && n > 0
        ? Math.floor(n)
        : DEFAULT_ROUTE_REQUEST_POLICY.ttlDays,
  };
}
