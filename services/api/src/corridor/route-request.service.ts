import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NotificationType, RouteRequest, TripStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationService } from '../notification/notification.service';
import { routeLabelAr } from './cities';
import {
  RouteRequestPolicy,
  baghdadDayKey,
  outstandingSince,
  readRouteRequestPolicy,
} from '../trip/route-request-policy';

/** ما يحتاجه الفان-آوت من الرحلة والممر — أي شيء بهذا الشكل ينفع. */
export interface FulfillingTrip {
  id: string;
  corridorId: string;
}

export interface FulfillCorridor {
  originCity: string;
  destCity: string;
}

/** نتيجة تسجيل طلب — الازدواج **نجاح**، لا خطأ. */
export interface RecordRouteRequestResult {
  request: RouteRequest;
  /** `true` = كان للراكب طلب على هذا الممر اليوم؛ ما أُنشئ صفّ جديد. */
  alreadyRequested: boolean;
}

/** صفّ واحد في شاشة الطلب مقابل العرض. */
export interface CorridorDemand {
  corridorId: string;
  originCity: string;
  destCity: string;
  corridorActive: boolean;
  /** طلبات غير محقّقة داخل النافذة — الترتيب عليها. */
  requestCount: number;
  /** كم راكباً مختلفاً وراء هذا العدد. */
  riderCount: number;
  /** أحدث طلب (ISO). */
  lastRequestedAt: string;
  /** رحلات حيّة على هذا الممر الآن. صفر = طلب بلا عرض. */
  activeTrips: number;
}

/**
 * إشارة الطلب على المسارات: مَن أراد ماذا، ومَن يُشعَر عندما يتوفّر.
 *
 * ## القاعدة الوحيدة التي تحكم كل شيء هنا
 *
 * **«مرة واحدة» لازم تكون صحيحة تحت التزامن، لا في المسار السعيد فقط.**
 * الميزة كلها عدّ وإشعار، وكلاهما ينكسر بصمت تحت السباق:
 *
 *  - نقرتان على شبكة عراقية بطيئة تصلان معاً → صفّان لطلب واحد → عدّ منتفخ
 *    يقرّر استقطاب سائق لمسار لا يستحقّه. **الحلّ فهرس فريد**، لا حارس
 *    بالتطبيق.
 *  - سائقان يعلنان على نفس الممر في نفس اللحظة → كلاهما يقرأ نفس الطلبات
 *    المعلّقة → الراكب يُشعَر مرتين. **الحلّ ختمٌ ذرّي** (`updateMany` ثم
 *    قراءة بالختم)، لا قراءة-ثم-كتابة.
 *
 * القاعدة الزمنية (عمر الطلب، ومعنى «اليوم») تعيش في `route-request-policy.ts`
 * بلا Prisma وبلا Nest، وهذه الخدمة هي الجسر إليها.
 */
@Injectable()
export class RouteRequestService {
  private readonly logger = new Logger(RouteRequestService.name);
  readonly policy: RouteRequestPolicy;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationService,
    config: ConfigService,
  ) {
    this.policy = readRouteRequestPolicy((key) => config.get<string>(key));
  }

  /**
   * الراكب يقول «أريد هذا المسار».
   *
   * **إعادة النقر نجاح، لا خطأ.** الراكب يقصد نفس الشيء في المرتين، والفشل
   * على نقرة ثانية يقرأ كعطل في التطبيق. نفس منطق «409 من `POST /ratings`
   * نجاحٌ متكافئ» في CLAUDE.md.
   *
   * الازدواج يُلتقط من **قيد قاعدة البيانات** (P2002) لا من قراءة سابقة:
   * القراءة-ثم-الكتابة تمرّر نقرتين متزامنتين، وهو بالضبط ما يفعله زرّ يُنقر
   * مرتين على شبكة بطيئة.
   */
  async record(
    riderId: string,
    input: { corridorId: string; requestedFor?: Date | null },
    now: Date = new Date(),
  ): Promise<RecordRouteRequestResult> {
    const corridor = await this.prisma.corridor.findUnique({
      where: { id: input.corridorId },
      select: { id: true },
    });
    if (!corridor) {
      throw new NotFoundException('الممر غير موجود.');
    }

    const requestedDay = baghdadDayKey(now);

    try {
      const request = await this.prisma.routeRequest.create({
        data: {
          riderId,
          corridorId: corridor.id,
          requestedFor: input.requestedFor ?? null,
          requestedDay,
        },
      });
      return { request, alreadyRequested: false };
    } catch (err) {
      if ((err as { code?: string })?.code !== 'P2002') throw err;

      // الصفّ موجود لهذا اليوم. نُرجعه كما هو — بلا لمس `requestedFor` ولا
      // `createdAt`: عمر الطلب يُحسب من **أول** مرة سأل، وإلا لجدّد الراكب
      // طلبه بلا قصد كلما فتح الشاشة، فما ينتهي أبداً.
      const existing = await this.prisma.routeRequest.findUnique({
        where: {
          riderId_corridorId_requestedDay: {
            riderId,
            corridorId: corridor.id,
            requestedDay,
          },
        },
      });
      if (!existing) throw err; // سباق نادر جداً: اختفى الصفّ بيننا.
      return { request: existing, alreadyRequested: true };
    }
  }

  /**
   * سائق أعلن رحلة على هذا الممر → أشعِر مَن طلبه.
   *
   * ## ليش «اختم ثم اقرأ» لا «اقرأ ثم أشعِر ثم اختم»
   *
   * الختم (`updateMany`) ذرّي على مستوى الصف: سائقان يعلنان في نفس اللحظة،
   * أحدهما فقط ينجح في ختم أي صفّ معيّن، فالراكب يُشعَر **مرة**. لو قرأنا
   * أولاً ثم أشعرنا، لقرأ الاثنان نفس الصفوف ولوصل إشعاران.
   *
   * `fulfilledByTripId` هو ما يجعل القراءة بعد الختم دقيقة: معرّف الرحلة
   * جديد في كل نداء، فالصفوف التي تحمله هي **بالضبط** التي ختمناها نحن. لا
   * يعطي `updateMany` الصفوفَ في Prisma، وهذا الختم يعوّضها بلا SQL خام.
   *
   * ## لا ترمي أبداً
   *
   * تُنادى **بعد** إنشاء الرحلة. الرحلة موجودة ومحجوزة ومرئية للركّاب؛ فشل
   * إشعار لا يجوز أن يقلب نداءً ناجحاً إلى خطأ يرى السائق فيه «تعذّر إعلان
   * الرحلة» بينما هي معلنة فعلاً. نفس سبب عدم رمي `NotificationService.send`.
   */
  async fulfillForTrip(
    trip: FulfillingTrip,
    corridor: FulfillCorridor,
    now: Date = new Date(),
  ): Promise<{ notified: number }> {
    try {
      const { count } = await this.prisma.routeRequest.updateMany({
        where: {
          corridorId: trip.corridorId,
          fulfilledAt: null,
          // منتهي الصلاحية لا يولّد إشعاراً — ويبقى غير محقّق عمداً: تحقيقه
          // كذبٌ في السجل، والاستعلامات كلها تستثنيه بنفس النافذة.
          createdAt: { gt: outstandingSince(this.policy, now) },
        },
        data: { fulfilledAt: now, fulfilledByTripId: trip.id },
      });
      if (count === 0) return { notified: 0 };

      const claimed = await this.prisma.routeRequest.findMany({
        where: { fulfilledByTripId: trip.id },
        select: { riderId: true },
      });

      // **راكب واحد = إشعار واحد.** قد يملك الراكب طلبين معلّقين على نفس
      // الممر (سأل أمس واليوم — الفهرس الفريد يمنع التكرار داخل اليوم فقط)،
      // وإشعاران عن رحلة واحدة يقرآن كعطل.
      const riderIds = [...new Set(claimed.map((r) => r.riderId))];

      const payload = {
        type: NotificationType.ROUTE_AVAILABLE,
        title: 'توفّرت رحلة على مسار طلبته',
        // بلا أرقام عمداً: النص يمرّ على خطوط ولوحات لا نتحكّم بخطّها، وقاعدة
        // «لا فاصلة نقطية بجانب رقم عربي» أصعب ضماناً كلما ابتعد النص عن
        // شاشاتنا. المدن كلمات، والتفاصيل على بعد نقرة.
        body: `${routeLabelAr(corridor.originCity, corridor.destCity)} — أعلن سائق رحلة على هذا المسار. ابحث الآن لحجز مقعدك.`,
        tripId: trip.id,
      };

      await Promise.all(riderIds.map((id) => this.notifications.send(id, payload)));
      return { notified: riderIds.length };
    } catch (err) {
      this.logger.error(
        `Route-request fan-out failed for trip ${trip.id}: ${(err as Error).message}`,
      );
      return { notified: 0 };
    }
  }

  /**
   * تجميع الطلب لكل ممر — الشاشة التي تقول للأدمن أين يستقطب سائقين.
   *
   * `unservedOnly` يعزل **القائمة القابلة للتنفيذ**: ممرات عليها طلب وما
   * عليها عرض. هذه هي الميزة كلها؛ الباقي سياق.
   */
  async demand(
    opts: { unservedOnly?: boolean } = {},
    now: Date = new Date(),
  ): Promise<CorridorDemand[]> {
    const since = outstandingSince(this.policy, now);

    const grouped = await this.prisma.routeRequest.groupBy({
      by: ['corridorId'],
      where: { fulfilledAt: null, createdAt: { gt: since } },
      _count: { _all: true },
      _max: { createdAt: true },
    });
    if (grouped.length === 0) return [];

    const corridorIds = grouped.map((g) => g.corridorId);

    const [corridors, riderRows, tripRows] = await Promise.all([
      this.prisma.corridor.findMany({
        where: { id: { in: corridorIds } },
        select: { id: true, originCity: true, destCity: true, active: true },
      }),
      // «كم راكباً» لا «كم صفّاً»: راكب سأل في ثلاثة أيام ليس ثلاثة ركّاب،
      // والفرق يقرّر ما إذا كان المسار مطلوباً أم شخصاً واحداً مصرّاً.
      this.prisma.routeRequest.findMany({
        where: {
          corridorId: { in: corridorIds },
          fulfilledAt: null,
          createdAt: { gt: since },
        },
        select: { corridorId: true, riderId: true },
      }),
      // العرض سؤال **حالة**، لا ساعة. رحلة «الآن» وقت مغادرتها يمضي لحظة
      // إعلانها، فأي `departureTime > now` مكتوب باليد يكذب عليها — وهي
      // بالضبط الرحلة التي تعني أن الممر مخدوم الآن.
      this.prisma.trip.groupBy({
        by: ['corridorId'],
        where: {
          corridorId: { in: corridorIds },
          status: { in: [TripStatus.OPEN, TripStatus.LOCKED, TripStatus.EN_ROUTE] },
        },
        _count: { _all: true },
      }),
    ]);

    const corridorById = new Map(corridors.map((c) => [c.id, c]));
    const activeByCorridor = new Map(tripRows.map((t) => [t.corridorId, t._count._all]));

    const ridersByCorridor = new Map<string, Set<string>>();
    for (const row of riderRows) {
      const set = ridersByCorridor.get(row.corridorId) ?? new Set<string>();
      set.add(row.riderId);
      ridersByCorridor.set(row.corridorId, set);
    }

    const rows: CorridorDemand[] = [];
    for (const g of grouped) {
      const corridor = corridorById.get(g.corridorId);
      if (!corridor) continue; // مستحيل عملياً (FK)، لكن الصفّ الفارغ أسوأ.
      const activeTrips = activeByCorridor.get(g.corridorId) ?? 0;
      if (opts.unservedOnly && activeTrips > 0) continue;

      rows.push({
        corridorId: corridor.id,
        originCity: corridor.originCity,
        destCity: corridor.destCity,
        corridorActive: corridor.active,
        requestCount: g._count._all,
        riderCount: ridersByCorridor.get(g.corridorId)?.size ?? 0,
        lastRequestedAt: (g._max.createdAt ?? new Date(0)).toISOString(),
        activeTrips,
      });
    }

    // الترتيب بالطلب، ثم بالأحدث: ممرّان بنفس العدد، الأنشط حديثاً أولاً.
    rows.sort(
      (a, b) =>
        b.requestCount - a.requestCount ||
        b.lastRequestedAt.localeCompare(a.lastRequestedAt),
    );
    return rows;
  }

}
