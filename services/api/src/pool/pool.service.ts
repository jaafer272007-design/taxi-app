import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  BookingStatus,
  NotificationType,
  PaymentMethod,
  PaymentStatus,
  Pool,
  PoolRaiseOutcome,
  PoolStatus,
  Prisma,
  RaiseResponse,
  SeatRequest,
  SeatRequestStatus,
  Trip,
  TripCreatedBy,
  TripStatus,
  TripType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { NotificationService } from '../notification/notification.service';
import { releaseSeat } from '../booking/seat-return';
import { routeLabelAr } from '../corridor/cities';
import {
  PoolPolicy,
  canProposeRaise,
  expiredPoolFilter,
  isViable,
  raiseDeadline,
  raiseRespondBy,
  readPoolPolicy,
} from './pool-policy';

/**
 * أسباب رفض الاستلام — **رموز، لا نصوص**.
 *
 * الخاسر في السباق ينبغي أن يقرأ «استلم سائق آخر» لا رسالة عامة: هي تعني
 * «ابحث عن تجمّع غيره»، بينما «انخفض العدد» تعني «انتظر» و«يتجاوز سعة سيارتك»
 * تعني «هذا ليس لك أصلاً» — ثلاث نصائح متعاكسة. والتطبيق لا يجوز أن يميّزها
 * بمطابقة نصّ عربي: أول تحسين صياغة كان سيكسر التفريع بصمت.
 */
export type PoolClaimRefusal =
  | 'POOL_ALREADY_CLAIMED'
  | 'POOL_EXPIRED'
  | 'POOL_WINDOW_PASSED'
  | 'POOL_NOT_VIABLE'
  | 'POOL_EXCEEDS_CAPACITY';

/** 409 يحمل رمزاً — نفس شكل `RIDER_BLOCKED_NO_SHOW` المستعمل في الحجز. */
function poolConflict(code: PoolClaimRefusal, message: string): ConflictException {
  return new ConflictException({
    statusCode: 409,
    error: 'Conflict',
    code,
    message,
  });
}

/** صفّ على لوحة السائق. */
export interface BoardPool {
  id: string;
  corridor: { id: string; originCity: string; destCity: string };
  windowStart: string;
  windowEnd: string;
  totalSeats: number;
  riderCount: number;
  pricePerSeat: number;
  /** إجمالي ما سيقبضه السائق نقداً إن استلم بهذا العدد. */
  estimatedFare: number;
  /** النقاط فقط — بلا أسماء ولا أرقام قبل الالتزام. */
  stops: {
    seatCount: number;
    pickup: { lat: number; lng: number; label: string };
    dropoff: { lat: number; lng: number; label: string };
  }[];
}

@Injectable()
export class PoolService {
  private readonly logger = new Logger(PoolService.name);
  readonly policy: PoolPolicy;

  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriverService,
    private readonly notifications: NotificationService,
    config: ConfigService,
  ) {
    this.policy = readPoolPolicy((key) => config.get<string>(key));
  }

  // ── اللوحة ───────────────────────────────────────────────────────────

  /**
   * التجمّعات التي يستطيع **هذا** السائق استلامها.
   *
   * ## لا أسماء ولا أرقام هنا
   *
   * اللوحة تعرض النقاط والمقاعد والسعر — لا اسم راكب ولا رقمه. نفس قاعدة
   * البحث في Phase 1: بيانات التواصل تأتي **بعد** الالتزام، وإلا صار تصفّح
   * اللوحة طريقةً لحصاد أرقام الناس.
   *
   * الفلترة بسعة مركبة السائق مقصودة: تجمّع أكبر من سيارته ليس خياراً له،
   * وعرضه ثم رفضه عند الاستلام إهدارٌ لوقته.
   */
  async board(driverUserId: string): Promise<BoardPool[]> {
    const profile = await this.drivers.assertApprovedDriver(driverUserId);
    const vehicle = await this.prisma.vehicle.findUnique({
      where: { driverId: profile.id },
    });
    if (!vehicle) {
      throw new BadRequestException('أضف مركبة قبل تصفّح التجمّعات.');
    }

    const capacity = Math.min(vehicle.seats, this.policy.maxSeats);
    const pools = await this.prisma.pool.findMany({
      where: {
        status: PoolStatus.FORMING,
        windowEnd: { gt: new Date() },
        totalSeats: { gte: this.policy.minSeats, lte: capacity },
      },
      include: {
        corridor: true,
        requests: { where: { status: SeatRequestStatus.PENDING } },
      },
      orderBy: [{ totalSeats: 'desc' }, { windowStart: 'asc' }],
      take: 50,
    });

    return pools.map((p) => ({
      id: p.id,
      corridor: {
        id: p.corridor.id,
        originCity: p.corridor.originCity,
        destCity: p.corridor.destCity,
      },
      windowStart: p.windowStart.toISOString(),
      windowEnd: p.windowEnd.toISOString(),
      totalSeats: p.totalSeats,
      riderCount: p.requests.length,
      pricePerSeat: p.pricePerSeat,
      estimatedFare: p.pricePerSeat * p.totalSeats,
      stops: p.requests.map((r) => ({
        seatCount: r.seatCount,
        pickup: { lat: r.pickupLat, lng: r.pickupLng, label: r.pickupLabel },
        dropoff: { lat: r.dropoffLat, lng: r.dropoffLng, label: r.dropoffLabel },
      })),
    }));
  }

  // ── الاستلام ─────────────────────────────────────────────────────────

  /**
   * سائق يستلم تجمّعاً → يصير **رحلة عادية** بحجوزات عادية.
   *
   * ## هنا ينتهي Phase 2 ويبدأ Phase 1 من جديد
   *
   * الناتج `Trip` بـ`createdBy = SYSTEM` و`SeatBooking` لكل طلب — صفوف لا
   * يميّزها شيء عن رحلة أعلنها سائق. كل ما بعد هذه اللحظة (البدء، الإكمال،
   * الإلغاء، عدم الحضور، التقييم، الأرباح، الإشعارات) يعمل بلا سطر جديد.
   * هذا هو معنى «لا نظام حجز موازٍ».
   *
   * ## السباق: سائقان يضغطان معاً
   *
   * الحارس `updateMany` مشروط بـ`status = FORMING` — نفس نمط حجز آخر مقعد.
   * ينجح **واحد** بالضبط؛ الخاسر يقرأ `count = 0` ويُردّ بـ409. لا يمكن أن
   * تُنشأ رحلتان لتجمّع واحد لأن كل شيء آخر يجري بعد ذلك الحارس داخل نفس
   * المعاملة.
   *
   * ## حساب المقاعد صحيح بالبناء
   *
   * `seatsAvailable = سعة − مقاعد التجمّع` تُحسب **داخل** المعاملة من
   * الطلبات المعلّقة فعلاً (لا من عدّاد مخزّن قد يكون سبقه إلغاء). فلا حاجة
   * لحارس تنافسي هنا: لا أحد غيرنا يكتب على رحلة لم تُنشأ بعد.
   */
  async claim(
    driverUserId: string,
    poolId: string,
    departureTimeIso?: string,
  ): Promise<{ trip: Trip; pool: Pool }> {
    const profile = await this.drivers.assertApprovedDriver(driverUserId);
    const vehicle = await this.prisma.vehicle.findUnique({
      where: { driverId: profile.id },
    });
    if (!vehicle) {
      throw new BadRequestException('أضف مركبة قبل استلام تجمّع.');
    }

    const pool = await this.prisma.pool.findUnique({ where: { id: poolId } });
    if (!pool) {
      throw new NotFoundException('التجمّع غير موجود.');
    }
    // «لم يعد متاحاً» كانت تخفي حقيقتين مختلفتين تماماً: تجمّعاً استلمه سائق
    // آخر قبل لحظة، وتجمّعاً انتهت مهلته. الأولى تعني «ابحث عن غيره الآن»
    // والثانية «لم يعد لهذا وجود» — فتُقالان الآن كلٌّ باسمها.
    if (pool.status !== PoolStatus.FORMING) {
      throw pool.status === PoolStatus.EXPIRED
        ? poolConflict('POOL_EXPIRED', 'انتهت مهلة هذا التجمّع ولم يعد قائماً.')
        : poolConflict(
            'POOL_ALREADY_CLAIMED',
            'استلم سائق آخر هذا التجمّع قبلك.',
          );
    }
    if (pool.windowEnd.getTime() <= Date.now()) {
      throw poolConflict('POOL_WINDOW_PASSED', 'انتهت نافذة هذا التجمّع.');
    }

    const departureTime = this.resolveDepartureTime(pool, departureTimeIso);

    const capacity = Math.min(vehicle.seats, this.policy.maxSeats);
    if (pool.totalSeats > capacity) {
      throw poolConflict(
        'POOL_EXCEEDS_CAPACITY',
        'عدد مقاعد التجمّع يتجاوز سعة سيارتك.',
      );
    }

    const result = await this.prisma.$transaction(async (tx) => {
      // ── الحارس الوحيد الذي يقرّر مَن يستلم ──────────────────────────
      const claimed = await tx.pool.updateMany({
        where: { id: poolId, status: PoolStatus.FORMING },
        data: {
          status: PoolStatus.CLAIMED,
          claimedByDriverId: profile.id,
          claimedAt: new Date(),
        },
      });
      if (claimed.count !== 1) {
        throw poolConflict(
          'POOL_ALREADY_CLAIMED',
          'استلم سائق آخر هذا التجمّع للتوّ.',
        );
      }

      const requests = await tx.seatRequest.findMany({
        where: { poolId, status: SeatRequestStatus.PENDING },
      });
      const pooledSeats = requests.reduce((sum, r) => sum + r.seatCount, 0);

      // يُعاد التحقّق **داخل** المعاملة: إلغاءٌ قد يكون هبط بالتجمّع تحت الحد
      // المجدي بين قراءتنا الأولى وحارسنا.
      if (!isViable(pooledSeats, this.policy)) {
        throw poolConflict(
          'POOL_NOT_VIABLE',
          'انخفض عدد المقاعد؛ لم يعد التجمّع مجدياً.',
        );
      }
      if (pooledSeats > capacity) {
        throw poolConflict(
          'POOL_EXCEEDS_CAPACITY',
          'عدد مقاعد التجمّع يتجاوز سعة سيارتك.',
        );
      }

      const seatsTotal = capacity;
      const seatsAvailable = seatsTotal - pooledSeats;

      const trip = await tx.trip.create({
        data: {
          corridorId: pool.corridorId,
          driverId: profile.id,
          vehicleId: vehicle.id,
          departureTime,
          departNow: false,
          seatsTotal,
          seatsAvailable,
          // سعر التجمّع كما رآه الركّاب والتزموا به.
          pricePerSeat: pool.pricePerSeat,
          // امتلأت السيارة بالتجمّع وحده → مقفلة فوراً، نفس قاعدة الحجز.
          status: seatsAvailable === 0 ? TripStatus.LOCKED : TripStatus.OPEN,
          // القيمة التي وُضعت في المخطط منذ Phase 1 لهذه اللحظة بالضبط.
          createdBy: TripCreatedBy.SYSTEM,
          tripType: TripType.GENERAL,
        },
      });

      for (const r of requests) {
        const booking = await tx.seatBooking.create({
          data: {
            tripId: trip.id,
            riderId: r.riderId,
            pickupLat: r.pickupLat,
            pickupLng: r.pickupLng,
            pickupLabel: r.pickupLabel,
            dropoffLat: r.dropoffLat,
            dropoffLng: r.dropoffLng,
            dropoffLabel: r.dropoffLabel,
            seatCount: r.seatCount,
            fare: pool.pricePerSeat * r.seatCount,
            paymentMethod: PaymentMethod.CASH,
            paymentStatus: PaymentStatus.PENDING,
            status: BookingStatus.CONFIRMED,
          },
        });
        await tx.seatRequest.update({
          where: { id: r.id },
          data: { status: SeatRequestStatus.MATCHED, bookingId: booking.id },
        });
      }

      const updatedPool = await tx.pool.update({
        where: { id: poolId },
        data: { tripId: trip.id, totalSeats: pooledSeats },
      });

      return { trip, pool: updatedPool, requests };
    });

    // بعد الـcommit — فشل إشعار لا يجوز أن يُلغي استلاماً تمّ.
    await this.notifyRiders(
      result.requests,
      {
        type: NotificationType.POOL_CLAIMED,
        title: 'تأكدت رحلتك',
        body: 'سائق استلم طلبك وصار عندك حجز مؤكد. التفاصيل في «حجوزاتي».',
        tripId: result.trip.id,
      },
      { perBooking: true },
    );

    return { trip: result.trip, pool: result.pool };
  }

  // ── ما يراه السائق عن تجمّعه بعد الاستلام ────────────────────────────

  /**
   * حالة الرفع على رحلة استلمها هذا السائق — **محسوبة على الخادم**.
   *
   * `canPropose` مشتقّ من **نفس** الشروط التي سيطبّقها `proposeRaise`، وهذا
   * هو الشرط كله: زرٌّ يعرضه التطبيق ثم يرفضه الخادم أسوأ من غياب الزر. نفس
   * القاعدة المثبّتة في `ratable` وفي `stage`.
   *
   * ويُرجع `blockedReason` بالعربية حين يكون الجواب «لا»: سائق يرى زراً معطّلاً
   * بلا سبب يفترض عطلاً، ويتصل بالدعم.
   *
   * أسماء الركّاب موجودة هنا عمداً — بعد الاستلام صار السائق يراها أصلاً في
   * `GET /trips/:id/bookings`، وقائمة ردود بلا أسماء («مقعدان: بانتظار») لا
   * يستطيع السائق أن يفعل بها شيئاً. لا أرقام هاتف: تلك تبقى في مسارها الوحيد.
   */
  async driverPoolForTrip(driverUserId: string, tripId: string) {
    const profile = await this.drivers.assertApprovedDriver(driverUserId);

    const pool = await this.prisma.pool.findFirst({
      where: { tripId },
      include: { corridor: true, raise: true },
    });
    // رحلة أعلنها سائق بنفسه لا تجمّع لها — وهذا ليس خطأ، بل الجواب.
    if (!pool) return null;
    if (pool.claimedByDriverId !== profile.id) {
      throw new ForbiddenException('هذه ليست رحلتك.');
    }

    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
    const members = await this.prisma.seatRequest.findMany({
      where: { poolId: pool.id },
      orderBy: { createdAt: 'asc' },
    });
    const live = members.filter((m) => m.status === SeatRequestStatus.MATCHED);

    // `SeatRequest` يحمل `riderId` بلا علاقة — والاسم حاجة عرضٍ لا تستحق
    // هجرة مخطط، فيُقرأ باستعلام ثانٍ صريح. `select` ضيّق عمداً: لا رقم هاتف
    // يمرّ من هنا، فذاك له مساره الوحيد.
    const riders = await this.prisma.user.findMany({
      where: { id: { in: members.map((m) => m.riderId) } },
      select: { id: true, name: true },
    });
    const nameOf = new Map(riders.map((r) => [r.id, r.name]));

    const now = new Date();
    const blockedReason = this.raiseBlockedReason(pool, trip, now);

    const raise = pool.raise;
    const seatsOf = (rs: typeof live) => rs.reduce((sum, r) => sum + r.seatCount, 0);

    return {
      poolId: pool.id,
      tripId,
      status: pool.status,
      corridor: {
        id: pool.corridor.id,
        originCity: pool.corridor.originCity,
        destCity: pool.corridor.destCity,
      },
      windowStart: pool.windowStart.toISOString(),
      windowEnd: pool.windowEnd.toISOString(),
      pricePerSeat: pool.pricePerSeat,
      /** سقف الممر — الحد الذي لا يتجاوزه أي اقتراح. */
      maxPricePerSeat: pool.corridor.maxPricePerSeat,
      seatsTaken: trip.seatsTotal - trip.seatsAvailable,
      seatsTotal: trip.seatsTotal,
      /** الحد الأدنى المجدي — به يفهم السائق ماذا يحدث لو رفض بعضهم. */
      minSeats: this.policy.minSeats,
      /** آخر لحظة يُقبل فيها اقتراح — يعرضها التطبيق بدل أن يجرّب ويُرفض. */
      raiseDeadline: raiseDeadline(pool, this.policy).toISOString(),
      responseMinutes: this.policy.raiseResponseMinutes,
      canPropose: blockedReason === null,
      blockedReason,
      raise: raise
        ? {
            oldPricePerSeat: raise.oldPricePerSeat,
            newPricePerSeat: raise.newPricePerSeat,
            respondBy: raise.respondBy.toISOString(),
            resolved: raise.resolvedAt !== null,
            outcome: raise.outcome,
            acceptedSeats: seatsOf(
              live.filter((m) => m.raiseResponse === RaiseResponse.ACCEPTED),
            ),
            declinedSeats: seatsOf(
              live.filter((m) => m.raiseResponse === RaiseResponse.DECLINED),
            ),
            pendingSeats: seatsOf(live.filter((m) => m.raiseResponse === null)),
            // كل الأعضاء، بمن فيهم مَن أُطلق بعد الحسم: «أين ذهب الثالث؟» سؤال
            // يطرحه السائق، وإخفاء الصف يجعل الجواب اختفاءً.
            responses: members.map((m) => ({
              riderName: nameOf.get(m.riderId) ?? null,
              seatCount: m.seatCount,
              response: m.raiseResponse,
              released: m.status !== SeatRequestStatus.MATCHED,
            })),
          }
        : null,
    };
  }

  /**
   * لماذا لا يستطيع هذا السائق اقتراح رفع الآن — أو `null` إن استطاع.
   *
   * كل فرع هنا يقابل رمياً في {@link proposeRaise}؛ هما يُقرآن معاً عمداً.
   */
  private raiseBlockedReason(
    pool: Pool & { raise: unknown },
    trip: Trip,
    now: Date,
  ): string | null {
    if (pool.raise) return 'اقترحت رفعاً على هذا التجمّع مسبقاً. لا يُسمح بأكثر من مرة.';
    if (pool.status !== PoolStatus.CLAIMED) {
      return 'لا يمكن اقتراح رفع على هذا التجمّع الآن.';
    }
    if (trip.status !== TripStatus.OPEN) {
      return 'لا يمكن اقتراح رفع بعد قفل الرحلة أو انطلاقها.';
    }
    if (trip.seatsAvailable <= 0) return 'امتلأت الرحلة؛ لا مبرّر لرفع السعر.';
    if (!canProposeRaise(pool, this.policy, now)) {
      return `فات وقت اقتراح رفع السعر. آخر موعد كان قبل ${this.policy.raiseBlackoutMinutes} دقيقة من بداية النافذة.`;
    }
    return null;
  }

  // ── رفع السعر ────────────────────────────────────────────────────────

  /**
   * السائق يقترح سعراً أعلى لتجمّع لم يملأ سيارته.
   *
   * كل حدّ هنا مفروض على الخادم، وكل واحد منها يجيب سؤال «ما الذي يمنع هذا
   * من أن يصير ابتزازاً»:
   *
   *  - **مرة واحدة** — يفرضها `@unique` على `PoolRaise.poolId`، فمحاولة ثانية
   *    تصطدم بقاعدة البيانات لا بفحص يسبقه سباق؛
   *  - **مسقوف** بـ`Corridor.maxPricePerSeat` الذي يضبطه الأدمن؛
   *  - **قبل مهلة** من بداية النافذة، فللرافض وقتٌ يدبّر فيه بديلاً؛
   *  - **صاحب الاستلام وحده** يقترح؛
   *  - و**فقط إن لم تمتلئ** السيارة: تجمّع ملأها ليس فيه ما يُبرّر رفعاً.
   */
  async proposeRaise(driverUserId: string, poolId: string, newPricePerSeat: number) {
    const profile = await this.drivers.assertApprovedDriver(driverUserId);

    const pool = await this.prisma.pool.findUnique({
      where: { id: poolId },
      include: { corridor: true, raise: true },
    });
    if (!pool) {
      throw new NotFoundException('التجمّع غير موجود.');
    }
    if (pool.claimedByDriverId !== profile.id) {
      throw new ForbiddenException('هذا ليس تجمّعك.');
    }
    if (pool.raise) {
      throw new ConflictException('اقترحت رفعاً على هذا التجمّع مسبقاً. لا يُسمح بأكثر من مرة.');
    }
    if (pool.status !== PoolStatus.CLAIMED || !pool.tripId) {
      throw new ConflictException('لا يمكن اقتراح رفع على هذا التجمّع الآن.');
    }

    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: pool.tripId } });
    if (trip.status !== TripStatus.OPEN) {
      throw new ConflictException('لا يمكن اقتراح رفع بعد قفل الرحلة أو انطلاقها.');
    }
    if (trip.seatsAvailable <= 0) {
      throw new ConflictException('امتلأت الرحلة؛ لا مبرّر لرفع السعر.');
    }

    if (newPricePerSeat <= pool.pricePerSeat) {
      throw new BadRequestException('السعر الجديد يجب أن يكون أعلى من الحالي.');
    }
    if (newPricePerSeat > pool.corridor.maxPricePerSeat) {
      throw new BadRequestException(
        `السعر الجديد يتجاوز الحد الأعلى للممر (${pool.corridor.maxPricePerSeat} IQD).`,
      );
    }

    const now = new Date();
    if (!canProposeRaise(pool, this.policy, now)) {
      throw new ConflictException(
        `فات وقت اقتراح رفع السعر. آخر موعد كان قبل ${this.policy.raiseBlackoutMinutes} دقيقة من بداية النافذة.`,
      );
    }

    const respondBy = raiseRespondBy(pool, this.policy, now);

    const raise = await this.prisma
      .$transaction(async (tx) => {
        const created = await tx.poolRaise.create({
          data: {
            poolId,
            proposedByDriverId: profile.id,
            oldPricePerSeat: pool.pricePerSeat,
            newPricePerSeat,
            respondBy,
          },
        });
        await tx.pool.update({
          where: { id: poolId },
          data: { status: PoolStatus.RAISE_PENDING },
        });
        return created;
      })
      .catch((err) => {
        // الحارس النهائي: سباق بين اقتراحين يصطدم بالفهرس الفريد.
        if ((err as { code?: string })?.code === 'P2002') {
          throw new ConflictException('اقترحت رفعاً على هذا التجمّع مسبقاً.');
        }
        throw err;
      });

    const members = await this.prisma.seatRequest.findMany({
      where: { poolId, status: SeatRequestStatus.MATCHED },
    });
    await this.notifyRiders(members, {
      type: NotificationType.POOL_RAISE_PROPOSED,
      title: 'السائق يقترح سعراً أعلى',
      body: `${routeLabelAr(pool.corridor.originCity, pool.corridor.destCity)} — وافق أو ارفض قبل انتهاء المهلة. الرفض بلا أي عقوبة.`,
      tripId: pool.tripId,
    });

    return raise;
  }

  /**
   * الراكب يوافق أو يرفض.
   *
   * الرفض فعل كامل الأهلية: يُطلق الراكب فوراً عند الحسم **بلا واقعة عدم
   * حضور ولا أي أثر سلبي** — هو لم يخلف موعداً، بل رفض عقداً جديداً عُرض
   * عليه بعد أن التزم بغيره.
   */
  async respondToRaise(riderId: string, seatRequestId: string, accept: boolean) {
    const request = await this.prisma.seatRequest.findUnique({
      where: { id: seatRequestId },
      include: { pool: { include: { raise: true } } },
    });
    if (!request) {
      throw new NotFoundException('الطلب غير موجود.');
    }
    if (request.riderId !== riderId) {
      throw new ForbiddenException('هذا ليس طلبك.');
    }
    const pool = request.pool;
    const raise = pool?.raise;
    if (!pool || !raise || pool.status !== PoolStatus.RAISE_PENDING) {
      throw new ConflictException('لا يوجد اقتراح سعر مفتوح على رحلتك.');
    }
    if (raise.resolvedAt) {
      throw new ConflictException('انتهت مهلة الردّ.');
    }
    if (Date.now() > raise.respondBy.getTime()) {
      throw new ConflictException('انتهت مهلة الردّ.');
    }

    const answered = await this.prisma.seatRequest.updateMany({
      where: { id: seatRequestId, raiseResponse: null },
      data: {
        raiseResponse: accept ? RaiseResponse.ACCEPTED : RaiseResponse.DECLINED,
        raiseRespondedAt: new Date(),
      },
    });
    if (answered.count !== 1) {
      throw new ConflictException('سجّلنا ردّك مسبقاً.');
    }

    // حسمٌ مبكر متى ردّ الجميع: لا معنى لانتظار مهلة لم يبقَ أحد يستعملها،
    // والسائق ينتظر جواباً ليقرّر.
    const stillWaiting = await this.prisma.seatRequest.count({
      where: {
        poolId: pool.id,
        status: SeatRequestStatus.MATCHED,
        raiseResponse: null,
      },
    });
    if (stillWaiting === 0) {
      await this.resolveRaise(pool.id);
    }

    return { recorded: true, accepted: accept };
  }

  /**
   * حسم الرفع — من آخر ردّ، أو من المهمّة الدورية عند انتهاء المهلة.
   *
   * **الصمت رفض.** راكب لم يردّ لا يُحمَّل سعراً لم يوافق عليه، وهذا يجعل
   * أسوأ حالات الشبكة (إشعار لم يصل) تنحاز لصالح الراكب لا ضدّه.
   *
   * كل شيء في معاملة واحدة: إطلاق نصف الركّاب ثم الفشل يترك مقاعد غير
   * محسوبة وسعراً بين اثنين.
   */
  async resolveRaise(poolId: string, now: Date = new Date()): Promise<void> {
    const resolved = await this.prisma.$transaction(async (tx) => {
      // حارس الحسم مرة واحدة: المهمّة الدورية وآخر ردّ قد يتسابقان.
      const claimedRaise = await tx.poolRaise.updateMany({
        where: { poolId, resolvedAt: null },
        data: { resolvedAt: now },
      });
      if (claimedRaise.count !== 1) return null;

      const raise = await tx.poolRaise.findUniqueOrThrow({ where: { poolId } });
      const pool = await tx.pool.findUniqueOrThrow({ where: { id: poolId } });
      const members = await tx.seatRequest.findMany({
        where: { poolId, status: SeatRequestStatus.MATCHED },
      });

      const accepted = members.filter((m) => m.raiseResponse === RaiseResponse.ACCEPTED);
      const released = members.filter((m) => m.raiseResponse !== RaiseResponse.ACCEPTED);
      const acceptedSeats = accepted.reduce((s, m) => s + m.seatCount, 0);

      const succeeded = isViable(acceptedSeats, this.policy);

      // المرفوضون يُطلقون في الحالتين: مقاعدهم تعود للرحلة بنفس الحساب الذي
      // يستعمله إلغاء الراكب — `releaseSeat`، لا نسخة ثانية منه.
      for (const m of released) {
        if (m.bookingId) await releaseSeat(tx, m.bookingId);
        await tx.seatRequest.update({
          where: { id: m.id },
          data: {
            status:
              m.raiseResponse === RaiseResponse.DECLINED
                ? SeatRequestStatus.DECLINED
                : SeatRequestStatus.EXPIRED,
          },
        });
      }

      if (succeeded) {
        await tx.trip.update({
          where: { id: pool.tripId! },
          data: { pricePerSeat: raise.newPricePerSeat },
        });
        for (const m of accepted) {
          if (!m.bookingId) continue;
          await tx.seatBooking.update({
            where: { id: m.bookingId },
            data: { fare: raise.newPricePerSeat * m.seatCount },
          });
        }
        await tx.pool.update({
          where: { id: poolId },
          data: { pricePerSeat: raise.newPricePerSeat, status: PoolStatus.CLAIMED },
        });
        await tx.poolRaise.update({
          where: { poolId },
          data: { outcome: PoolRaiseOutcome.ACCEPTED },
        });
      } else {
        // تحت الحد الأدنى → لا رحلة. مَن قَبِل يُطلق أيضاً، ولا يُحاسَب أحد.
        for (const m of accepted) {
          if (m.bookingId) await releaseSeat(tx, m.bookingId);
          await tx.seatRequest.update({
            where: { id: m.id },
            data: { status: SeatRequestStatus.EXPIRED },
          });
        }
        await tx.trip.update({
          where: { id: pool.tripId! },
          data: { status: TripStatus.CANCELLED },
        });
        await tx.pool.update({
          where: { id: poolId },
          data: { status: PoolStatus.EXPIRED },
        });
        await tx.poolRaise.update({
          where: { poolId },
          data: { outcome: PoolRaiseOutcome.FAILED },
        });
      }

      return { pool, raise, accepted, released, acceptedSeats, succeeded };
    });

    if (!resolved) return;

    const { pool, raise, accepted, released, acceptedSeats, succeeded } = resolved;

    // المُطلَقون — نتيجتهم واحدة سواء نجح الرفع أم لا: خرجوا بلا التزام.
    await this.notifyRiders(released, {
      type: NotificationType.POOL_EXPIRED,
      title: 'أُطلق طلبك',
      body: 'لم توافق على السعر الجديد، فأُلغي حجزك بلا أي رسوم أو أثر على حسابك.',
      tripId: pool.tripId ?? undefined,
    });

    if (!succeeded) {
      // مَن قَبِل كان ينتظر السفر — وهذا الخبر يكلّفه رحلته، فهو نفس حدث
      // «أُلغيت الرحلة» الذي يستحق حواراً حاجباً في التطبيق.
      await this.notifyRiders(accepted, {
        type: NotificationType.TRIP_CANCELLED,
        title: 'أُلغيت الرحلة',
        body: 'لم يكتمل العدد بعد تعديل السعر، فأُلغيت الرحلة. لن تُحاسب على شيء.',
        tripId: pool.tripId ?? undefined,
      });
    }

    await this.notifyDriver(raise.proposedByDriverId, {
      type: NotificationType.POOL_RAISE_RESOLVED,
      title: succeeded ? 'قُبل السعر الجديد' : 'لم يكتمل العدد',
      body: succeeded
        ? 'وافق ما يكفي من الركّاب. الرحلة تمضي بالسعر الجديد.'
        : 'لم يوافق ما يكفي من الركّاب، فأُلغيت الرحلة.',
      tripId: pool.tripId ?? undefined,
    });

    this.logger.log(
      `Raise on pool ${poolId} resolved: ${succeeded ? 'ACCEPTED' : 'FAILED'} ` +
        `(${acceptedSeats} seat(s) accepted, ${released.length} released)`,
    );
  }

  // ── مساعدات ──────────────────────────────────────────────────────────

  /** وقت المغادرة: افتراضه بداية النافذة، وأي بديل يجب أن يقع داخلها. */
  private resolveDepartureTime(pool: Pool, iso?: string): Date {
    if (!iso) return pool.windowStart;
    const at = new Date(iso);
    if (Number.isNaN(at.getTime())) {
      throw new BadRequestException('وقت المغادرة غير صالح.');
    }
    if (
      at.getTime() < pool.windowStart.getTime() ||
      at.getTime() > pool.windowEnd.getTime()
    ) {
      throw new BadRequestException('وقت المغادرة خارج نافذة التجمّع.');
    }
    return at;
  }

  /** يُشعِر ركّاب مجموعة طلبات. لا يرمي — يُنادى دائماً بعد الـcommit. */
  private async notifyRiders(
    requests: readonly SeatRequest[],
    payload: {
      type: NotificationType;
      title: string;
      body: string;
      tripId?: string;
    },
    opts: { perBooking?: boolean } = {},
  ): Promise<void> {
    await Promise.all(
      requests.map((r) =>
        this.notifications.send(r.riderId, {
          ...payload,
          bookingId: opts.perBooking ? (r.bookingId ?? undefined) : undefined,
        }),
      ),
    );
  }

  /** يحلّ `DriverProfile.id` إلى `User.id` ويُشعِره. */
  private async notifyDriver(
    driverProfileId: string,
    payload: { type: NotificationType; title: string; body: string; tripId?: string },
  ): Promise<void> {
    const driver = await this.prisma.driverProfile.findUnique({
      where: { id: driverProfileId },
      select: { userId: true },
    });
    if (driver) await this.notifications.send(driver.userId, payload);
  }

  /** آخر موعد لاقتراح رفع — يعرضه التطبيق للسائق بدل أن يجرّب ويُرفض. */
  raiseDeadlineFor(pool: Pool): Date {
    return raiseDeadline(pool, this.policy);
  }

  // ── الكنس ────────────────────────────────────────────────────────────

  /**
   * تجمّعات مضت نافذتها بلا سائق → تنتهي، ويُطلق ركّابها ويُخبَرون.
   *
   * **الإخبار هو الجزء المهم، لا التنظيف.** راكب طلب مقعداً لصباح الخميس
   * ولم يستلم أحد تجمّعه سيقف ينتظر إن لم نقل له شيئاً — وهو بالضبط الضرر
   * الذي يجعل `TRIP_CANCELLED` حدثاً حاجباً في Phase 1.
   *
   * الرؤية لا تعتمد على هذه المهمّة: اللوحة تفلتر بـ`windowEnd > now`
   * والاستلام يرفض تجمّعاً مضت نافذته، فلو لم تعمل المهمّة أبداً لبقيت
   * صفوف قديمة فقط — لا تجمّع شبح يُستلَم. صحّةٌ في الاستعلام، وترتيبٌ على
   * الجدولة.
   */
  async expireUnclaimedPools(now: Date = new Date()): Promise<number> {
    const stale = await this.prisma.pool.findMany({
      where: { status: PoolStatus.FORMING, ...expiredPoolFilter(now) },
      select: { id: true },
    });
    if (stale.length === 0) return 0;

    let expired = 0;
    for (const { id } of stale) {
      const released = await this.prisma.$transaction(async (tx) => {
        // حارس السباق: تجمّع استلمه سائق بين القراءة والكتابة يبقى له.
        const marked = await tx.pool.updateMany({
          where: { id, status: PoolStatus.FORMING },
          data: { status: PoolStatus.EXPIRED },
        });
        if (marked.count !== 1) return [];

        const members = await tx.seatRequest.findMany({
          where: { poolId: id, status: SeatRequestStatus.PENDING },
        });
        await tx.seatRequest.updateMany({
          where: { poolId: id, status: SeatRequestStatus.PENDING },
          data: { status: SeatRequestStatus.EXPIRED },
        });
        return members;
      });

      if (released.length === 0) continue;
      expired += 1;
      await this.notifyRiders(released, {
        type: NotificationType.POOL_EXPIRED,
        title: 'لم يتوفّر سائق',
        body: 'انتهت مهلة طلبك بلا سائق. لم تُحاسب على شيء — جرّب وقتاً آخر أو ابحث في الرحلات المعلنة.',
      });
    }
    return expired;
  }

  /**
   * اقتراحات رفع مضت مهلتها → تُحسم، وغير الرادّين يُحتسبون رافضين.
   *
   * الحسم نفسه في {@link resolveRaise}، فالمهمّة الدورية وآخر ردّ يمرّان من
   * الحارس نفسه ولا يمكن أن يُحسم رفع مرتين.
   */
  async resolveDueRaises(now: Date = new Date()): Promise<number> {
    const due = await this.prisma.poolRaise.findMany({
      where: { resolvedAt: null, respondBy: { lte: now } },
      select: { poolId: true },
    });
    for (const { poolId } of due) {
      await this.resolveRaise(poolId, now);
    }
    return due.length;
  }
}
