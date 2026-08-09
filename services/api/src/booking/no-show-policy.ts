/**
 * عواقب عدم الحضور — السياسة في مكان واحد.
 *
 * ## لماذا سمعة + إيقاف مؤقت، لا رسوم
 *
 * الدفع نقدي بالكامل في Phase 1: ما في وسيلة دفع مخزّنة نخصم منها، فأي
 * «رسم عدم حضور» يبقى رقماً بلا تحصيل — عقوبة على الورق فقط. الشيء الوحيد
 * الذي نملكه فعلاً هو **الوصول إلى المنصّة**، فهو ما نستعمله.
 *
 * ## لماذا هذا مهم أصلاً
 *
 * السائق يخسر مقعداً كاملاً بلا مقابل. على سيارة بأربعة مقاعد هذا **٢٥٪ من
 * دخل الرحلة**، ولا شيء يمنع التكرار. السائقون هم القيد الأصعب في هذا
 * السوق؛ تطبيق يكلّفهم مالاً بلا حماية يخسرهم.
 *
 * ## القاعدة
 *
 * [NoShowPolicy.threshold] وقائع **غير ملغاة** خلال [NoShowPolicy.windowDays]
 * يوماً → يُمنع الراكب من إنشاء حجوزات جديدة لمدة
 * [NoShowPolicy.blockDays] تبدأ من **آخر واقعة**.
 *
 * الأرقام قابلة للضبط من البيئة عمداً: هذه أرقام سياسة، لا ثوابت هندسية،
 * وأول تشغيل حقيقي سيغيّرها. راجع `.env.example`.
 *
 * ## ما لا يفعله الإيقاف
 *
 * **لا يلغي الحجوزات القائمة.** الراكب المحجوز له مقعد يبقى له؛ الإيقاف
 * يمنع الجديد فقط. إلغاء حجز مؤكَّد عقوبةً يضرّ السائق أيضاً — يخسر راكباً
 * كان سيأتي — ويحوّل عقوبة على سلوك سابق إلى ضرر على رحلة لا علاقة لها.
 */

/** الأرقام القابلة للضبط. */
export interface NoShowPolicy {
  /** كم واقعة غير ملغاة توجب الإيقاف. */
  threshold: number;
  /** طول النافذة المتدحرجة بالأيام. */
  windowDays: number;
  /** مدة الإيقاف بالأيام، تبدأ من آخر واقعة. */
  blockDays: number;
}

/**
 * نقطة البداية: ٣ مرات خلال ٣٠ يوماً → إيقاف ٧ أيام.
 *
 * ٣ وليس ٢: مرة واحدة حادث، ومرتان قد تكونان سوء حظ (ازدحام، طوارئ عائلية).
 * ٣ خلال شهر نمط. و٧ أيام تُشعَر ولا تطرد — الهدف تغيير السلوك لا خسارة راكب.
 */
export const DEFAULT_NO_SHOW_POLICY: NoShowPolicy = {
  threshold: 3,
  windowDays: 30,
  blockDays: 7,
};

const DAY_MS = 24 * 60 * 60 * 1000;

/** واقعة كما تحتاجها القاعدة — أي شيء يحمل `createdAt` ينفع. */
export interface NoShowOccurrence {
  createdAt: Date;
}

export interface BlockState {
  /** هل يُمنع هذا الراكب من الحجز الآن؟ */
  blocked: boolean;
  /** عدد الوقائع غير الملغاة داخل النافذة — يُعرض للأدمن وللسائق. */
  countInWindow: number;
  /** متى يُرفع الإيقاف. `null` عندما لا يكون موقوفاً. */
  blockedUntil: Date | null;
}

/**
 * قيّم حالة راكب من وقائعه.
 *
 * تستقبل الوقائع **غير الملغاة** (الاستعلام يتكفّل بذلك)، وتتولّى هي حساب
 * النافذة — حتى تبقى القاعدة كلها في دالة واحدة قابلة للاختبار بلا قاعدة
 * بيانات، وتبقى للاستعلام مسؤولية واحدة: مَن وأيها ملغاة.
 */
export function evaluateBlock(
  occurrences: readonly NoShowOccurrence[],
  policy: NoShowPolicy = DEFAULT_NO_SHOW_POLICY,
  now: Date = new Date(),
): BlockState {
  const windowStart = now.getTime() - policy.windowDays * DAY_MS;
  const inWindow = occurrences.filter((o) => o.createdAt.getTime() > windowStart);

  if (inWindow.length < policy.threshold) {
    return { blocked: false, countInWindow: inWindow.length, blockedUntil: null };
  }

  // الإيقاف يبدأ من آخر واقعة، لا من لحظة العدّ — وإلا لتجدّد الإيقاف نفسه
  // كلما فتح الراكب التطبيق، فما ينتهي أبداً ما دامت الوقائع داخل النافذة.
  const latest = Math.max(...inWindow.map((o) => o.createdAt.getTime()));
  const until = new Date(latest + policy.blockDays * DAY_MS);

  return {
    blocked: until.getTime() > now.getTime(),
    countInWindow: inWindow.length,
    blockedUntil: until.getTime() > now.getTime() ? until : null,
  };
}

/** بداية النافذة — يستعملها الاستعلام حتى لا يقرأ تاريخ الراكب كله. */
export function windowStart(policy: NoShowPolicy, now: Date = new Date()): Date {
  return new Date(now.getTime() - policy.windowDays * DAY_MS);
}

/** يقرأ السياسة من البيئة، مع الرجوع للافتراضي عند الغياب أو القيمة الفاسدة. */
export function readNoShowPolicy(get: (key: string) => string | undefined): NoShowPolicy {
  const num = (key: string, fallback: number): number => {
    const raw = get(key);
    if (raw === undefined || String(raw).trim() === '') return fallback;
    const n = Number(raw);
    // قيمة فاسدة ترجع للافتراضي بدل أن تُسقط الإقلاع: هذه أرقام سياسة،
    // وخطأ مطبعي في متغيّر بيئة ما يستاهل توقّف الخدمة.
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
  };
  return {
    threshold: num('NO_SHOW_BLOCK_THRESHOLD', DEFAULT_NO_SHOW_POLICY.threshold),
    windowDays: num('NO_SHOW_WINDOW_DAYS', DEFAULT_NO_SHOW_POLICY.windowDays),
    blockDays: num('NO_SHOW_BLOCK_DAYS', DEFAULT_NO_SHOW_POLICY.blockDays),
  };
}

/**
 * تاريخ عربي قصير («١٥ آب») بتوقيت بغداد.
 *
 * الرسالة تذكر **متى يُرفع الإيقاف**: «موقوف» بلا تاريخ تترك الراكب بلا شيء
 * يفعله، وهي بالضبط الحالة التي تولّد اتصالاً بالدعم.
 */
export function formatArabicDate(d: Date): string {
  return new Intl.DateTimeFormat('ar-IQ', {
    day: 'numeric',
    month: 'long',
    timeZone: 'Asia/Baghdad',
  }).format(d);
}

/** رسالة الرفض التي يراها الراكب. */
export function blockedMessage(state: BlockState, policy: NoShowPolicy): string {
  const until = state.blockedUntil ? formatArabicDate(state.blockedUntil) : '';
  return (
    `تم إيقاف الحجز مؤقتاً بسبب تكرار عدم الحضور ` +
    `(${state.countInWindow} مرات خلال ${policy.windowDays} يوماً). ` +
    `يمكنك الحجز مجدداً في ${until}. ` +
    `حجوزاتك الحالية لم تتأثر. إذا كان هناك ظرف طارئ راجع الدعم.`
  );
}
