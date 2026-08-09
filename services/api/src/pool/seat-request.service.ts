import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  Pool,
  PoolStatus,
  Prisma,
  SeatRequest,
  SeatRequestStatus,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NoShowService } from '../booking/no-show.service';
import { CreateSeatRequestDto } from './dto/create-seat-request.dto';
import {
  PoolPolicy,
  intersectWindows,
  isViable,
  maxWindowMs,
  overlappingPoolFilter,
  poolJoinFilter,
  readPoolPolicy,
  windowsOverlap,
} from './pool-policy';

/** الطلبات التي ما زالت حيّة — أي شيء غير هذه انتهى. */
const LIVE_REQUEST_STATUSES = [
  SeatRequestStatus.PENDING,
  SeatRequestStatus.MATCHED,
] as const;

/**
 * حالة الطلب **كما يفهمها الراكب**، لا كما تُخزَّن.
 *
 * `SeatRequestStatus` يجيب «كيف انتهى هذا الصف»، وهذا يجيب «ماذا أنتظر الآن»
 * — وهما سؤالان مختلفان: `PENDING` وحدها لا تفرّق بين «ما زلنا نجمّع ركّاباً»
 * و«اكتمل العدد وننتظر سائقاً»، والفرق هو كل ما يريد الراكب معرفته.
 */
export type SeatRequestStage =
  | 'WAITING_FOR_RIDERS'
  | 'WAITING_FOR_DRIVER'
  | 'RAISE_PENDING'
  | 'CLAIMED'
  | 'CANCELLED'
  | 'DECLINED'
  | 'EXPIRED';

/** صفّ طلب مع ممرّه وتجمّعه ورفع التجمّع — ما يحتاجه `serialize`. */
type SeatRequestWithPool = Prisma.SeatRequestGetPayload<{
  include: { corridor: true; pool: { include: { raise: true } } };
}>;

@Injectable()
export class SeatRequestService {
  readonly policy: PoolPolicy;

  constructor(
    private readonly prisma: PrismaService,
    private readonly noShows: NoShowService,
    config: ConfigService,
  ) {
    this.policy = readPoolPolicy((key) => config.get<string>(key));
  }

  /**
   * الراكب يطلب مقعداً: يُنشأ الطلب **وينضم لتجمّع** في معاملة واحدة.
   *
   * ## البوّابات قبل أي كتابة، بنفس ترتيب `BookingService.book`
   *
   * الطلب التزام لا استفسار: إن استلمه سائق صار حجزاً مؤكداً بلا سؤال آخر.
   * فكل ما يمنع الحجز يجب أن يمنع الطلب، **وقبل المعاملة** حتى لا تُضعف
   * ضمانتها — نفس الموضع الذي يحتلّه فحص الجنس وفحص الإيقاف هناك. لو تُرك
   * الفحص لما بعد، لكان راكب موقوف يدخل تجمّعاً ويُخرَج منه لاحقاً، وهو أسوأ
   * من رفضه الآن: السائق يكون قد استلم على أساس مقاعده.
   */
  async create(riderId: string, dto: CreateSeatRequestDto) {
    const corridor = await this.prisma.corridor.findUnique({
      where: { id: dto.corridorId },
    });
    if (!corridor) {
      throw new NotFoundException('الممر غير موجود.');
    }
    if (!corridor.active) {
      throw new BadRequestException('هذا الممر غير مفعّل حالياً.');
    }

    const window = this.parseWindow(dto.windowStart, dto.windowEnd);

    if (dto.seatCount > this.policy.maxSeats) {
      throw new BadRequestException(
        `أقصى عدد مقاعد في الطلب ${this.policy.maxSeats}.`,
      );
    }

    // ملف مكتمل — نفس قاعدة الحجز. لا يُفحص الجنس لأكثر من ذلك: تجمّعات هذه
    // المرحلة كلها `GENERAL`؛ الرحلات النسائية-العائلية تبقى على مسار Phase 1
    // (السائق يعلنها والراكبة تحجزها). حدّ معروف، مذكور في البريف.
    const rider = await this.prisma.user.findUnique({
      where: { id: riderId },
      select: { gender: true },
    });
    if (!rider || rider.gender == null) {
      throw new ForbiddenException('يرجى إكمال ملفك الشخصي (تحديد الجنس) قبل الطلب.');
    }

    // الإيقاف بسبب تكرار عدم الحضور — نفس بوّابة الحجز ونفس الشكل المبنيّ للرد.
    const block = await this.noShows.blockStateFor(riderId);
    if (block.blocked) {
      throw new ForbiddenException({
        statusCode: 403,
        error: 'Forbidden',
        code: 'RIDER_BLOCKED_NO_SHOW',
        message: this.noShows.message(block),
        blockedUntil: block.blockedUntil?.toISOString() ?? null,
        noShowCount: block.countInWindow,
        threshold: this.noShows.policy.threshold,
        windowDays: this.noShows.policy.windowDays,
      });
    }

    // طلب واحد حيّ لكل راكب على ممرّ بنافذة متقاطعة.
    //
    // نفس منطق «حجز واحد لكل راكب لكل رحلة»: طلبان متقاطعان ليسا ما يقصده
    // الراكب أبداً — يقصد مقاعد أكثر — وهما يلتفّان على سقف المقاعد ويعطيان
    // السائق مجموعتين لراكب واحد.
    const clashing = await this.prisma.seatRequest.findFirst({
      where: {
        riderId,
        corridorId: corridor.id,
        status: { in: [...LIVE_REQUEST_STATUSES] },
        ...this.overlapWhere(window),
      },
      select: { id: true },
    });
    if (clashing) {
      throw new ConflictException(
        'لديك طلب على هذا المسار في نفس الوقت. ألغِ الطلب السابق أو اختر وقتاً آخر.',
      );
    }

    const created = await this.prisma.$transaction(async (tx) => {
      const pool = await this.joinOrOpenPool(tx, corridor, window, dto.seatCount);
      return tx.seatRequest.create({
        data: {
          riderId,
          corridorId: corridor.id,
          poolId: pool.id,
          windowStart: window.windowStart,
          windowEnd: window.windowEnd,
          seatCount: dto.seatCount,
          pickupLat: dto.pickup.lat,
          pickupLng: dto.pickup.lng,
          pickupLabel: dto.pickup.label,
          dropoffLat: dto.dropoff.lat,
          dropoffLng: dto.dropoff.lng,
          dropoffLabel: dto.dropoff.label,
          status: SeatRequestStatus.PENDING,
        },
      });
    });

    // **نفس شكل `GET /seat-requests/mine`**، لا صفّ Prisma خام.
    //
    // الصفّ الخام يخرج بلا `stage` وبلا `corridor` وبنقاط مسطّحة
    // (`pickupLat`…)، أي شكل ثانٍ لنفس الشيء — والتطبيق كان سيحتاج مُحلِّلاً
    // ثانياً له، وهو بالضبط ما يجعل حقلاً جديداً يُضاف في مكان وينسى في الآخر.
    // القراءة الإضافية ثمن بسيط مقابل مسار تسلسل واحد.
    const full = await this.prisma.seatRequest.findUniqueOrThrow({
      where: { id: created.id },
      include: { corridor: true, pool: { include: { raise: true } } },
    });
    return this.serialize(full);
  }

  /**
   * ينضم لتجمّع متقاطع، أو يفتح واحداً.
   *
   * الانضمام **مقارنة-وتبديل** (`updateMany` بحارس يعيد تأكيد النافذة التي
   * قرأناها)، لا قراءة-ثم-كتابة. طلبان يصلان معاً على شبكة بطيئة هما الحالة
   * العادية لا النادرة، وقراءة-ثم-كتابة كانت ستُدخل الاثنين وتتجاوز السقف.
   *
   * فشل الحارس ليس خطأً: نفتح تجمّعاً جديداً. أسوأ ما يحدث تحت تزاحم نادر
   * تجمّعان بدل واحد — نتيجة صحيحة، لا فاسدة.
   */
  private async joinOrOpenPool(
    tx: Prisma.TransactionClient,
    corridor: { id: string; suggestedPricePerSeat: number },
    window: { windowStart: Date; windowEnd: Date },
    seatCount: number,
  ): Promise<Pool> {
    const now = new Date();
    const candidates = await tx.pool.findMany({
      where: {
        corridorId: corridor.id,
        status: PoolStatus.FORMING,
        windowEnd: { gt: now },
        totalSeats: { lte: this.policy.maxSeats - seatCount },
        ...overlappingPoolFilter(window),
      },
      // الأكثر امتلاءً أولاً: يملأ تجمّعاً قائماً قبل أن يفتح ثانياً، فتصل
      // التجمّعات إلى الحد المجدي أسرع بدل أن تتناثر الطلبات على تجمّعات
      // ناقصة لا يستلمها أحد.
      orderBy: [{ totalSeats: 'desc' }, { windowStart: 'asc' }],
      take: 5,
    });

    for (const candidate of candidates) {
      // حارس مزدوج: المرشّح جاء من استعلام يطبّق نفس القاعدة، لكن الصيغة
      // النقية هي المرجع — و`pool-policy.spec.ts` يؤكد أنهما تتفقان.
      if (!windowsOverlap(candidate, window)) continue;
      const merged = intersectWindows(candidate, window);

      const joined = await tx.pool.updateMany({
        where: poolJoinFilter(candidate.id, candidate, seatCount, this.policy),
        data: {
          totalSeats: { increment: seatCount },
          windowStart: merged.windowStart,
          windowEnd: merged.windowEnd,
        },
      });
      if (joined.count === 1) {
        return tx.pool.findUniqueOrThrow({ where: { id: candidate.id } });
      }
    }

    return tx.pool.create({
      data: {
        corridorId: corridor.id,
        windowStart: window.windowStart,
        windowEnd: window.windowEnd,
        totalSeats: seatCount,
        // منسوخ وقت التكوين، مثل `Trip.pricePerSeat`: إعادة تسعير الممر لاحقاً
        // لا تغيّر سعراً رآه راكب والتزم به.
        pricePerSeat: corridor.suggestedPricePerSeat,
        status: PoolStatus.FORMING,
      },
    });
  }

  /**
   * ما يراه الراكب عن طلبه، **محسوباً على الخادم**.
   *
   * الفرق بين «ننتظر ركّاباً» و«ننتظر سائقاً» يتطلّب `POOL_MIN_SEATS`، وهو رقم
   * سياسة. لو أرسلنا `poolSeats` وتركنا التطبيق يقارنه بـ٢ مكتوبة في Dart،
   * لصار للسياسة نسختان — وأول تغيير للعتبة يجعل التطبيق يكذب على الراكب.
   *
   * نفس القاعدة المثبّتة في «قادمة/سابقة»: القرار يعيش في مكان واحد، والتطبيق
   * **يضع البطاقة حيث يُقال له** ولا يعيد اشتقاق الحكم.
   */
  private stageOf(r: {
    status: SeatRequestStatus;
    raiseResponse: unknown;
    pool: { status: PoolStatus; totalSeats: number; raise: unknown } | null;
  }): SeatRequestStage {
    switch (r.status) {
      case SeatRequestStatus.CANCELLED:
        return 'CANCELLED';
      case SeatRequestStatus.DECLINED:
        return 'DECLINED';
      case SeatRequestStatus.EXPIRED:
        return 'EXPIRED';
      case SeatRequestStatus.MATCHED:
        // رفعٌ مفتوح لم يردّ عليه الراكب بعد هو الحالة الوحيدة التي تطلب منه
        // فعلاً الآن — ولذلك تسبق «تأكّدت».
        if (r.pool?.status === PoolStatus.RAISE_PENDING && r.raiseResponse == null) {
          return 'RAISE_PENDING';
        }
        return 'CLAIMED';
      case SeatRequestStatus.PENDING:
      default:
        if (!r.pool) return 'WAITING_FOR_RIDERS';
        return isViable(r.pool.totalSeats, this.policy)
          ? 'WAITING_FOR_DRIVER'
          : 'WAITING_FOR_RIDERS';
    }
  }

  /** طلبات هذا الراكب، الأحدث أولاً، مع حالة تجمّعها. */
  async listMine(riderId: string) {
    const requests = await this.prisma.seatRequest.findMany({
      where: { riderId },
      orderBy: { createdAt: 'desc' },
      include: { corridor: true, pool: { include: { raise: true } } },
      take: 50,
    });

    return requests.map((r) => this.serialize(r));
  }

  /**
   * شكل الطلب كما يراه الراكب — **مسار تسلسل واحد** لكل من الإنشاء والقائمة.
   *
   * التطبيق يحلّل شكلاً واحداً؛ نسختان كانتا ستعنيان أن حقلاً يُضاف هنا ويُنسى
   * هناك، ولن يكشفه شيء حتى تظهر شاشة ناقصة عند المستخدم.
   */
  private serialize(r: SeatRequestWithPool) {
    return {
      id: r.id,
      status: r.status,
      /** ما يُعرض للراكب — محسوب هنا، لا يُشتقّ في التطبيق. */
      stage: this.stageOf(r),
      seatCount: r.seatCount,
      windowStart: r.windowStart.toISOString(),
      windowEnd: r.windowEnd.toISOString(),
      pickup: { lat: r.pickupLat, lng: r.pickupLng, label: r.pickupLabel },
      dropoff: { lat: r.dropoffLat, lng: r.dropoffLng, label: r.dropoffLabel },
      corridor: {
        id: r.corridor.id,
        originCity: r.corridor.originCity,
        destCity: r.corridor.destCity,
      },
      // السعر الذي التزم به الراكب. يأتي من التجمّع لا من الممر: الممر قد
      // يكون أُعيد تسعيره بعد الطلب.
      pricePerSeat: r.pool?.pricePerSeat ?? null,
      bookingId: r.bookingId,
      tripId: r.pool?.tripId ?? null,
      poolStatus: r.pool?.status ?? null,
      poolSeats: r.pool?.totalSeats ?? null,
      // الرفع، إن كان على تجمّعه واحد ولم يُحسم بعد — هذا ما يحتاجه التطبيق
      // ليعرض شاشة «وافق أو ارفض».
      raise:
        r.pool?.raise && r.pool.raise.resolvedAt === null
          ? {
              oldPricePerSeat: r.pool.raise.oldPricePerSeat,
              newPricePerSeat: r.pool.raise.newPricePerSeat,
              respondBy: r.pool.raise.respondBy.toISOString(),
              myResponse: r.raiseResponse,
            }
          : null,
      createdAt: r.createdAt.toISOString(),
    };
  }

  /**
   * الراكب يلغي طلبه قبل الاستلام.
   *
   * بعد الاستلام لم يعد هذا طلباً بل **حجزاً**، ويُلغى من مسار الحجز نفسه
   * (`DELETE /bookings/:id`) بكل قواعده — الإرجاع الذرّي للمقعد، وإعادة فتح
   * الرحلة، وإشعار السائق. مسار إلغاء ثانٍ للشيء نفسه هو بالضبط ما يعني
   * «نظام حجز موازٍ».
   */
  async cancel(riderId: string, id: string): Promise<SeatRequest> {
    const request = await this.prisma.seatRequest.findUnique({ where: { id } });
    if (!request) {
      throw new NotFoundException('الطلب غير موجود.');
    }
    if (request.riderId !== riderId) {
      throw new ForbiddenException('هذا ليس طلبك.');
    }
    if (request.status === SeatRequestStatus.MATCHED) {
      throw new ConflictException(
        'تم تأكيد رحلتك بالفعل. ألغِ الحجز من «حجوزاتي» بدل الطلب.',
      );
    }
    if (request.status !== SeatRequestStatus.PENDING) {
      throw new ConflictException('هذا الطلب لم يعد قائماً.');
    }

    return this.prisma.$transaction(async (tx) => {
      // حارس السباق: إلغاء واحد فقط يمرّ، فالمقاعد تُخصم من التجمّع مرة واحدة.
      const cancelled = await tx.seatRequest.updateMany({
        where: { id, status: SeatRequestStatus.PENDING },
        data: { status: SeatRequestStatus.CANCELLED },
      });
      if (cancelled.count !== 1) {
        throw new ConflictException('تم إلغاء الطلب مسبقاً.');
      }

      if (request.poolId) {
        // النافذة **لا تتّسع** مرة أخرى، وهذا مقصود: توسيعها يتطلّب قراءة كل
        // الأعضاء الباقين، والنافذة الضيّقة تبقى صحيحة للجميع — كل عضو باقٍ
        // يتقاطع معها بالتعريف. تحفّظٌ آمن أرخص من إعادة حساب.
        const pool = await tx.pool.update({
          where: { id: request.poolId },
          data: { totalSeats: { decrement: request.seatCount } },
        });
        // تجمّع فرغ تماماً لا شيء فيه ليُستلم.
        if (pool.totalSeats <= 0 && pool.status === PoolStatus.FORMING) {
          await tx.pool.update({
            where: { id: pool.id },
            data: { status: PoolStatus.EXPIRED },
          });
        }
      }

      return tx.seatRequest.findUniqueOrThrow({ where: { id } });
    });
  }

  // ── مساعدات ──────────────────────────────────────────────────────────

  /** يتحقّق من النافذة ويعيدها كتواريخ. */
  private parseWindow(startIso: string, endIso: string) {
    const windowStart = new Date(startIso);
    const windowEnd = new Date(endIso);
    if (Number.isNaN(windowStart.getTime()) || Number.isNaN(windowEnd.getTime())) {
      throw new BadRequestException('نافذة الوقت غير صالحة.');
    }
    if (windowEnd.getTime() <= windowStart.getTime()) {
      throw new BadRequestException('أمتع وقت يجب أن يكون بعد أبكر وقت.');
    }
    if (windowEnd.getTime() <= Date.now()) {
      throw new BadRequestException('نافذة الوقت في الماضي.');
    }
    if (windowEnd.getTime() - windowStart.getTime() > maxWindowMs(this.policy)) {
      throw new BadRequestException(
        `النافذة أوسع من ${this.policy.maxWindowHours} ساعات.`,
      );
    }
    return { windowStart, windowEnd };
  }

  /** «يتقاطع مع هذه النافذة» كشرط على صفوف `SeatRequest`. */
  private overlapWhere(window: { windowStart: Date; windowEnd: Date }) {
    return {
      windowStart: { lte: window.windowEnd },
      windowEnd: { gte: window.windowStart },
    };
  }
}
