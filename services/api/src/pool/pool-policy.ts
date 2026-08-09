import { Prisma } from '@prisma/client';

/**
 * التجميع (Phase 2) — القاعدة كلها في مكان واحد، بلا Prisma وبلا Nest.
 *
 * ## القاعدة التي يجب أن يفهمها راكب
 *
 * **طلبان يتجمّعان إذا اشتركا في الممر وتقاطعت نافذتاهما.** لا شيء آخر: لا
 * تحسين مسار، ولا تقليل انحراف، ولا تشابه نقاط. راكب سأل «ليش ما انضممت؟»
 * يستحق جواباً من جملة واحدة، وهذه هي.
 *
 * نافذة التجمّع هي **تقاطع** نوافذ أعضائه: تضيق مع كل عضو ولا تتّسع أبداً،
 * فأي وقت داخلها يناسب الجميع بالتعريف. وهذا أيضاً ما يجعل الانضمام آمناً
 * تحت التزامن — راجع `poolJoinFilter`.
 *
 * ## لماذا العتبات بيئة لا ثوابت
 *
 * هذه أرقام **سياسة**: أول شهر تشغيل حقيقي سيغيّرها. قيمة فاسدة ترجع
 * للافتراضي بدل أن تُسقط الإقلاع، بنفس نمط `no-show-policy.ts`.
 */

/** الأرقام القابلة للضبط. */
export interface PoolPolicy {
  /**
   * سقف مقاعد التجمّع = أكبر مركبة مدعومة.
   *
   * تجمّع أكبر من أي سيارة نملكها لا يستطيع أحد استلامه، فهو ليس تجمّعاً بل
   * طلبات محبوسة.
   */
  maxSeats: number;

  /**
   * أقل عدد مقاعد يجعل التجمّع مجدياً.
   *
   * يحكم شيئين معاً وعمداً: متى يظهر التجمّع على اللوحة، وكم قبولاً يلزم بعد
   * رفع السعر. رقم واحد لسؤال واحد — «هل تستحق هذه الرحلة أن تُقاد؟» —
   * وعتبتان مختلفتان لنفس السؤال كانتا ستتباعدان.
   */
  minSeats: number;

  /**
   * لا يُقترح رفع سعر داخل هذه المهلة قبل بداية النافذة (بالدقائق).
   *
   * الراكب الذي يرفض يجب أن يبقى أمامه وقت يدبّر فيه بديلاً. رفعٌ قبل ربع
   * ساعة من الانطلاق ليس عرضاً، بل أمر واقع.
   */
  raiseBlackoutMinutes: number;

  /**
   * مهلة ردّ الراكب على الرفع (بالدقائق). عدم الردّ = رفض.
   *
   * **يجب أن تكون أقصر من `raiseBlackoutMinutes`**، وإلا انتهت المهلة بعد
   * انطلاق الرحلة. الحساب لا الذوق: الرفع ممنوع بعد
   * `windowStart − blackout`، فأقصى `respondBy` هو
   * `windowStart − blackout + response`؛ وما دام `response < blackout` فهو
   * قبل `windowStart` دائماً. راجع {@link raiseRespondBy} — تقصّها أيضاً
   * احتياطاً حتى لو ضُبطت البيئة على العكس.
   */
  raiseResponseMinutes: number;

  /**
   * أوسع نافذة يقبلها طلب واحد (بالساعات).
   *
   * نافذة بلا حدّ تتقاطع مع كل شيء، فتتجمّع طلبات لا يجمعها شيء حقيقي —
   * والسائق يستلم مجموعة لا تريد السفر في نفس الساعة.
   */
  maxWindowHours: number;
}

/**
 * نقطة البداية.
 *
 * `maxSeats: 4` — سقف مقاعد الرحلة في البريف §9، وهو أكبر ما تحمله سيارة
 * صالون عراقية عملياً.
 *
 * `minSeats: 2` — تجمّع بمقعد واحد ليس تجمّعاً، وقيادة ساعة بين محافظتين
 * لراكب واحد بسعر مقعد مشترك خسارة للسائق. الراكب الوحيد ليس متروكاً: أمامه
 * رحلات السائقين المعلنة (Phase 1)، و«أبلغنا أنك تريد هذا المسار» إن لم يكن
 * على ممرّه أحد.
 *
 * `raiseBlackoutMinutes: 30` / `raiseResponseMinutes: 10` — نصف ساعة تكفي
 * لتدبير بديل، وعشر دقائق تكفي للردّ على إشعار.
 */
export const DEFAULT_POOL_POLICY: PoolPolicy = {
  maxSeats: 4,
  minSeats: 2,
  raiseBlackoutMinutes: 30,
  raiseResponseMinutes: 10,
  maxWindowHours: 6,
};

const MINUTE_MS = 60_000;

/** نافذة وقت — أي شيء بهذا الشكل ينفع. */
export interface TimeWindow {
  windowStart: Date;
  windowEnd: Date;
}

// ── قاعدة التجميع ──────────────────────────────────────────────────────

/**
 * هل تتقاطع النافذتان؟
 *
 * تقاطع **مغلق**: نافذة تنتهي عند اللحظة التي تبدأ فيها الأخرى تتقاطع معها،
 * لأن تلك اللحظة وقت مغادرة يقبله الاثنان فعلاً. حدّ مفتوح كان سيرفض حالة
 * صحيحة تماماً بلا سبب يمكن شرحه لراكب.
 */
export function windowsOverlap(a: TimeWindow, b: TimeWindow): boolean {
  return a.windowStart.getTime() <= b.windowEnd.getTime() &&
    b.windowStart.getTime() <= a.windowEnd.getTime();
}

/** التقاطع نفسه. غير معرّف إن لم تتقاطعا — تحقّق بـ{@link windowsOverlap} أولاً. */
export function intersectWindows(a: TimeWindow, b: TimeWindow): TimeWindow {
  return {
    windowStart: new Date(Math.max(a.windowStart.getTime(), b.windowStart.getTime())),
    windowEnd: new Date(Math.min(a.windowEnd.getTime(), b.windowEnd.getTime())),
  };
}

/**
 * {@link windowsOverlap} كمرشّح قاعدة بيانات — الصيغة الثانية لنفس القاعدة.
 *
 * الصيغتان **يجب أن تتفقا**، و`pool-policy.spec.ts` يؤكد ذلك على نفس
 * العيّنات. هذا نفس الدرس الذي أنتج `trip-window.ts`: قاعدة واحدة مكتوبة
 * مرتين هي بالضبط الشكل الذي تتباعد فيه.
 */
export function overlappingPoolFilter(want: TimeWindow): Prisma.PoolWhereInput {
  return {
    windowStart: { lte: want.windowEnd },
    windowEnd: { gte: want.windowStart },
  };
}

/**
 * حارس الانضمام الذرّي.
 *
 * ينضم الطلب بـ`updateMany` مشروط بهذا الـ`where`، لا بقراءة ثم كتابة. ما
 * يُعاد تأكيده هنا هو ما يجعل «انضمام متزامن» آمناً:
 *
 *  - `status: FORMING` — لا تنضم لتجمّع استُلم للتوّ؛
 *  - `totalSeats` ≤ السقف ناقص مقاعدنا — لا تجاوز للسقف تحت التزامن؛
 *  - **النافذة كما قرأناها** — مقارنة-وتبديل: لو ضيّقها منضمّ آخر بيننا،
 *    فشلَ التحديث بدل أن ندخل تجمّعاً ما عدنا نتقاطع معه.
 *
 * الفشل ليس خطأً: المنادي يفتح تجمّعاً جديداً. أسوأ نتيجة تجمّعان بدل واحد
 * تحت تزاحم نادر — وهي نتيجة صحيحة، لا فاسدة.
 */
export function poolJoinFilter(
  poolId: string,
  seenWindow: TimeWindow,
  seatCount: number,
  policy: PoolPolicy = DEFAULT_POOL_POLICY,
): Prisma.PoolWhereInput {
  return {
    id: poolId,
    status: 'FORMING',
    totalSeats: { lte: policy.maxSeats - seatCount },
    windowStart: seenWindow.windowStart,
    windowEnd: seenWindow.windowEnd,
  };
}

// ── الصلاحية والمهل ────────────────────────────────────────────────────

/** هل ما زال التجمّع قابلاً للاستلام زمنياً؟ */
export function isPoolLive(pool: TimeWindow, now: Date = new Date()): boolean {
  return pool.windowEnd.getTime() > now.getTime();
}

/** المكمّل — ما يكنسه المهمّة الدورية. الصيغتان يجب أن تتفقا. */
export function expiredPoolFilter(now: Date): Prisma.PoolWhereInput {
  return { windowEnd: { lte: now } };
}

/**
 * آخر لحظة يجوز فيها اقتراح رفع.
 *
 * قبل بداية النافذة بـ{@link PoolPolicy.raiseBlackoutMinutes} — بداية النافذة
 * لا نهايتها: الرحلة قد تنطلق في أبكر وقت يناسب الجميع، وهو ما يجب أن يبقى
 * أمام الرافض وقتٌ قبله.
 */
export function raiseDeadline(
  pool: TimeWindow,
  policy: PoolPolicy = DEFAULT_POOL_POLICY,
): Date {
  return new Date(pool.windowStart.getTime() - policy.raiseBlackoutMinutes * MINUTE_MS);
}

/** هل يجوز اقتراح رفع الآن؟ */
export function canProposeRaise(
  pool: TimeWindow,
  policy: PoolPolicy = DEFAULT_POOL_POLICY,
  now: Date = new Date(),
): boolean {
  return now.getTime() < raiseDeadline(pool, policy).getTime();
}

/**
 * مهلة ردّ الراكب.
 *
 * مقصوصة عند بداية النافذة حتى لو ضُبطت البيئة بحيث تتجاوز المهلةُ المنعَ —
 * مهلة تنتهي بعد انطلاق الرحلة تعني ركّاباً يُحسم مصيرهم وهم في الطريق.
 */
export function raiseRespondBy(
  pool: TimeWindow,
  policy: PoolPolicy = DEFAULT_POOL_POLICY,
  now: Date = new Date(),
): Date {
  const wanted = now.getTime() + policy.raiseResponseMinutes * MINUTE_MS;
  return new Date(Math.min(wanted, pool.windowStart.getTime()));
}

/** هل بلغ التجمّع الحدّ الذي يجعله مجدياً؟ */
export function isViable(totalSeats: number, policy: PoolPolicy = DEFAULT_POOL_POLICY): boolean {
  return totalSeats >= policy.minSeats;
}

/** أوسع نافذة مسموحة لطلب واحد، بالمللي ثانية. */
export function maxWindowMs(policy: PoolPolicy = DEFAULT_POOL_POLICY): number {
  return policy.maxWindowHours * 60 * MINUTE_MS;
}

// ── قراءة البيئة ───────────────────────────────────────────────────────

/** يقرأ السياسة من البيئة، مع الرجوع للافتراضي عند الغياب أو الفساد. */
export function readPoolPolicy(get: (key: string) => string | undefined): PoolPolicy {
  const num = (key: string, fallback: number): number => {
    const raw = get(key);
    if (raw === undefined || String(raw).trim() === '') return fallback;
    const n = Number(raw);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
  };

  const policy: PoolPolicy = {
    maxSeats: num('POOL_MAX_SEATS', DEFAULT_POOL_POLICY.maxSeats),
    minSeats: num('POOL_MIN_SEATS', DEFAULT_POOL_POLICY.minSeats),
    raiseBlackoutMinutes: num(
      'POOL_RAISE_BLACKOUT_MINUTES',
      DEFAULT_POOL_POLICY.raiseBlackoutMinutes,
    ),
    raiseResponseMinutes: num(
      'POOL_RAISE_RESPONSE_MINUTES',
      DEFAULT_POOL_POLICY.raiseResponseMinutes,
    ),
    maxWindowHours: num('POOL_MAX_WINDOW_HOURS', DEFAULT_POOL_POLICY.maxWindowHours),
  };

  // حدّ أدنى أكبر من السقف يعني لوحة فارغة إلى الأبد — تشكيلة لا يمكن أن
  // تكون مقصودة، فتُردّ للافتراضي بدل أن تعمل بصمت ولا تنتج شيئاً.
  if (policy.minSeats > policy.maxSeats) {
    policy.minSeats = DEFAULT_POOL_POLICY.minSeats;
    policy.maxSeats = DEFAULT_POOL_POLICY.maxSeats;
  }
  return policy;
}
