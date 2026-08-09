import { ConfigService } from '@nestjs/config';
import { BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import {
  BookingStatus,
  DriverStatus,
  Gender,
  NotificationType,
  PoolRaiseOutcome,
  PoolStatus,
  SeatRequestStatus,
  TripCreatedBy,
  TripStatus,
  UserRole,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { StorageService } from '../storage/storage.service';
import { NotificationService } from '../notification/notification.service';
import { NoShowService } from '../booking/no-show.service';
import { BookingService } from '../booking/booking.service';
import { PoolService } from './pool.service';
import { SeatRequestService } from './seat-request.service';

/**
 * التجميع (Phase 2) — مقابل قاعدة بيانات حقيقية.
 *
 * كل خطأ حقيقي في هذا المستودع كان **خطأ تفاعل** مرّ من اختبارات الوحدة:
 * شرط `where` خاطئ، حالتان تتسابقان، عدّاد لا يتفق مع الصفوف. وPhase 2 كلها
 * من هذا الطراز — الانضمام تحت التزامن، استلامان في نفس اللحظة، حساب مقاعد
 * يعبر حدود جدولين. Prisma مُقلَّد لا يطبّق `where` أصلاً، فما كان ليثبت أياً
 * من هذا.
 *
 * يحتاج DATABASE_URL. يُشغَّل بـ`npm run test:int`.
 */

const MIN = 60_000;
const HOUR = 60 * MIN;

let prisma: PrismaService;
let seatRequests: SeatRequestService;
let pools: PoolService;
let bookings: BookingService;
let noShows: NoShowService;

interface Fixture {
  tag: string;
  corridorId: string;
  otherCorridorId: string;
  driverUserId: string;
  driverProfileId: string;
  driver2UserId: string;
  driver2ProfileId: string;
  riderAId: string;
  riderBId: string;
  riderCId: string;
}

const SUGGESTED = 10_000;
const MAX_PRICE = 20_000;

async function seedFixture(): Promise<Fixture> {
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const [corridor, otherCorridor] = await Promise.all([
    prisma.corridor.create({
      data: {
        originCity: `PL-${tag}-A`,
        destCity: `PL-${tag}-B`,
        suggestedPricePerSeat: SUGGESTED,
        minPricePerSeat: 5_000,
        maxPricePerSeat: MAX_PRICE,
        active: true,
      },
    }),
    prisma.corridor.create({
      data: {
        originCity: `PL-${tag}-C`,
        destCity: `PL-${tag}-D`,
        suggestedPricePerSeat: SUGGESTED,
        minPricePerSeat: 5_000,
        maxPricePerSeat: MAX_PRICE,
        active: true,
      },
    }),
  ]);

  const mkDriver = (suffix: string, plate: string, seats: number) =>
    prisma.user.create({
      data: {
        phone: `+9647${tag}${suffix}`,
        name: `سائق ${suffix}`,
        gender: Gender.MALE,
        roles: [UserRole.RIDER, UserRole.DRIVER],
        driver: {
          create: {
            status: DriverStatus.APPROVED,
            vehicle: {
              create: { make: 'Toyota', model: 'Corolla', plate, color: 'أبيض', seats },
            },
          },
        },
      },
      include: { driver: true },
    });

  const [d1, d2] = await Promise.all([
    mkDriver('0001', `PL-${tag}-1`, 4),
    mkDriver('0002', `PL-${tag}-2`, 4),
  ]);

  const [riderA, riderB, riderC] = await Promise.all(
    ['1111', '2222', '3333'].map((s, i) =>
      prisma.user.create({
        data: {
          phone: `+9647${tag}${s}`,
          name: `راكب ${i}`,
          gender: Gender.FEMALE,
          roles: [UserRole.RIDER],
        },
      }),
    ),
  );

  return {
    tag,
    corridorId: corridor.id,
    otherCorridorId: otherCorridor.id,
    driverUserId: d1.id,
    driverProfileId: d1.driver!.id,
    driver2UserId: d2.id,
    driver2ProfileId: d2.driver!.id,
    riderAId: riderA.id,
    riderBId: riderB.id,
    riderCId: riderC.id,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  const userIds = [f.driverUserId, f.driver2UserId, f.riderAId, f.riderBId, f.riderCId];
  const corridorIds = [f.corridorId, f.otherCorridorId];
  const driverIds = [f.driverProfileId, f.driver2ProfileId];

  await prisma.notification.deleteMany({ where: { userId: { in: userIds } } });
  await prisma.poolRaise.deleteMany({ where: { pool: { corridorId: { in: corridorIds } } } });
  await prisma.seatRequest.deleteMany({ where: { corridorId: { in: corridorIds } } });
  await prisma.pool.deleteMany({ where: { corridorId: { in: corridorIds } } });
  await prisma.noShowRecord.deleteMany({ where: { riderId: { in: userIds } } });
  await prisma.seatBooking.deleteMany({ where: { trip: { corridorId: { in: corridorIds } } } });
  await prisma.earningsRecord.deleteMany({ where: { driverId: { in: driverIds } } });
  await prisma.trip.deleteMany({ where: { corridorId: { in: corridorIds } } });
  await prisma.vehicle.deleteMany({ where: { driverId: { in: driverIds } } });
  await prisma.document.deleteMany({ where: { driverId: { in: driverIds } } });
  await prisma.driverProfile.deleteMany({ where: { id: { in: driverIds } } });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  await prisma.corridor.deleteMany({ where: { id: { in: corridorIds } } });
}

/**
 * طلب مقعد بنافذة نسبية بالساعات من `base`.
 *
 * `base` صريح لا `Date.now()` داخل الدالة: نداءان متتاليان يفصلهما ميلي ثانية،
 * فنافذتان يُفترض أن تتلامسا عند نفس اللحظة تفوّت إحداهما الأخرى بفارق لا
 * علاقة له بالقاعدة المُختبَرة.
 */
async function request(
  f: Fixture,
  riderId: string,
  fromHours: number,
  toHours: number,
  seatCount = 1,
  corridorId = f.corridorId,
  base = Date.now(),
) {
  const created = await seatRequests.create(riderId, {
    corridorId,
    windowStart: new Date(base + fromHours * HOUR).toISOString(),
    windowEnd: new Date(base + toHours * HOUR).toISOString(),
    pickup: { lat: 32.0, lng: 44.3, label: 'نقطة الانطلاق' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'نقطة الوصول' },
    seatCount,
  });
  // الصفّ الخام لا الحمولة المُسلسلة: هذه الاختبارات عن التجميع نفسه — عن
  // `poolId` والنوافذ كتواريخ — لا عن الشكل الذي يراه التطبيق. شكل الإنشاء
  // يُختبر مرة واحدة، في اختباره الخاص أدناه.
  return prisma.seatRequest.findUniqueOrThrow({ where: { id: created.id } });
}

function notificationsOf(userId: string, type: NotificationType) {
  return prisma.notification.findMany({ where: { userId, type } });
}

beforeAll(() => {
  prisma = new PrismaService();
  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  noShows = new NoShowService(prisma, config);
  seatRequests = new SeatRequestService(prisma, noShows, config);
  pools = new PoolService(prisma, drivers, notifications, config);
  bookings = new BookingService(prisma, drivers, notifications, noShows);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('pooling (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  // ── القاعدة: نفس الممر + تقاطع النوافذ ────────────────────────────────

  it('two OVERLAPPING requests land in the SAME pool, and its window is the intersection', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    const b = await request(f, f.riderBId, 4, 8);

    expect(b.poolId).toBe(a.poolId);

    const pool = await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } });
    expect(pool.totalSeats).toBe(2);
    // التقاطع: [4h, 6h] — أي وقت داخله يناسب الاثنين.
    expect(pool.windowStart.getTime()).toBeCloseTo(b.windowStart.getTime(), -3);
    expect(pool.windowEnd.getTime()).toBeCloseTo(a.windowEnd.getTime(), -3);
    // السعر منسوخ من اقتراح الممر، لا مقروء منه لاحقاً.
    expect(pool.pricePerSeat).toBe(SUGGESTED);
  });

  it('two NON-overlapping requests do NOT pool', async () => {
    const a = await request(f, f.riderAId, 2, 3);
    const b = await request(f, f.riderBId, 5, 6);

    expect(b.poolId).not.toBe(a.poolId);
    const poolCount = await prisma.pool.count({ where: { corridorId: f.corridorId } });
    expect(poolCount).toBe(2);
  });

  it('requests on DIFFERENT corridors never pool, however well the times match', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    const b = await request(f, f.riderBId, 3, 6, 1, f.otherCorridorId);
    expect(b.poolId).not.toBe(a.poolId);
  });

  it('windows that merely touch DO pool — that instant suits both', async () => {
    const base = Date.now();
    const a = await request(f, f.riderAId, 2, 4, 1, f.corridorId, base);
    const b = await request(f, f.riderBId, 4, 6, 1, f.corridorId, base);
    expect(b.poolId).toBe(a.poolId);

    // والتقاطع لحظة واحدة — نافذة صفرية الطول، وهي وقت مغادرة صالح.
    const pool = await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } });
    expect(pool.windowStart.toISOString()).toBe(pool.windowEnd.toISOString());
  });

  it('a pool never exceeds the seat cap; the overflow opens its own', async () => {
    const a = await request(f, f.riderAId, 3, 6, 3);
    const b = await request(f, f.riderBId, 3, 6, 3);
    expect(b.poolId).not.toBe(a.poolId);

    const first = await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } });
    expect(first.totalSeats).toBe(3);
    expect(first.totalSeats).toBeLessThanOrEqual(pools.policy.maxSeats);
  });

  it('refuses a second live request from the same rider on an overlapping window', async () => {
    await request(f, f.riderAId, 3, 6);
    // ليست ما يقصده الراكب أبداً — يقصد مقاعد أكثر — وتلتفّ على سقف المقاعد.
    await expect(request(f, f.riderAId, 4, 7)).rejects.toBeInstanceOf(ConflictException);
    // ...لكن نافذة لا تتقاطع مسموحة: رحلة أخرى في يوم آخر.
    await expect(request(f, f.riderAId, 20, 22)).resolves.toBeTruthy();
  });

  it('refuses a window in the past, an inverted one, and one wider than the cap', async () => {
    await expect(request(f, f.riderAId, -4, -2)).rejects.toBeInstanceOf(BadRequestException);
    await expect(request(f, f.riderAId, 6, 3)).rejects.toBeInstanceOf(BadRequestException);
    await expect(request(f, f.riderAId, 1, 20)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses a rider blocked for no-shows — the same gate as booking', async () => {
    // التجمّع يصير حجزاً بلا سؤال آخر، فما يمنع الحجز يجب أن يمنع الطلب.
    const now = Date.now();
    await prisma.noShowRecord.createMany({
      data: [1, 3, 5].map((d, i) => ({
        riderId: f.riderAId,
        tripId: `pl-${f.tag}-t${i}`,
        bookingId: `pl-${f.tag}-b${i}`,
        seatCount: 1,
        createdAt: new Date(now - d * 24 * HOUR),
      })),
    });
    expect((await noShows.blockStateFor(f.riderAId)).blocked).toBe(true);

    await expect(request(f, f.riderAId, 3, 6)).rejects.toBeInstanceOf(ForbiddenException);
    expect(await prisma.seatRequest.count({ where: { riderId: f.riderAId } })).toBe(0);
  });

  it('cancelling a request returns its seats to the pool', async () => {
    const a = await request(f, f.riderAId, 3, 6, 2);
    await request(f, f.riderBId, 3, 6, 1);
    expect((await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } })).totalSeats).toBe(3);

    await seatRequests.cancel(f.riderAId, a.id);

    const pool = await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } });
    expect(pool.totalSeats).toBe(1);
    expect(pool.status).toBe(PoolStatus.FORMING);
  });

  it('cancelling the last request retires the pool', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await seatRequests.cancel(f.riderAId, a.id);
    expect((await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } })).status).toBe(
      PoolStatus.EXPIRED,
    );
  });

  // ── ما يراه الراكب ───────────────────────────────────────────────────

  it('the STAGE distinguishes waiting-for-riders from waiting-for-a-driver', async () => {
    // الفرق يحتاج POOL_MIN_SEATS، وهو رقم سياسة: يُحسب هنا فلا يعيد التطبيق
    // اشتقاقه بعتبة مكتوبة في Dart تتباعد عند أول تغيير.
    const base = Date.now();
    await request(f, f.riderAId, 3, 6, 1, f.corridorId, base);
    let mine = await seatRequests.listMine(f.riderAId);
    expect(mine[0].stage).toBe('WAITING_FOR_RIDERS');

    await request(f, f.riderBId, 3, 6, 1, f.corridorId, base);
    mine = await seatRequests.listMine(f.riderAId);
    expect(mine[0].stage).toBe('WAITING_FOR_DRIVER');
    expect(mine[0].poolSeats).toBe(2);
    // والسعر الذي التزم به، من التجمّع لا من الممر.
    expect(mine[0].pricePerSeat).toBe(SUGGESTED);
  });

  it('the stage becomes CLAIMED and carries the bookingId the app opens', async () => {
    const base = Date.now();
    const a = await request(f, f.riderAId, 3, 6, 1, f.corridorId, base);
    await request(f, f.riderBId, 3, 6, 1, f.corridorId, base);
    await pools.claim(f.driverUserId, a.poolId!);

    const [mine] = await seatRequests.listMine(f.riderAId);
    expect(mine.stage).toBe('CLAIMED');
    // هذا هو الجسر إلى واجهة الحجوزات القائمة — بدونه لا يعرف التطبيق أي
    // حجز يفتح، فيصير الطلب عالماً موازياً بدل أن يتحوّل إلى حجز.
    expect(mine.bookingId).toBeTruthy();
    expect(mine.tripId).toBeTruthy();
  });

  it('an open raise the rider has not answered outranks CLAIMED', async () => {
    const base = Date.now();
    const a = await request(f, f.riderAId, 3, 6, 2, f.corridorId, base);
    const b = await request(f, f.riderBId, 3, 6, 1, f.corridorId, base);
    await pools.claim(f.driverUserId, a.poolId!);
    await pools.proposeRaise(f.driverUserId, a.poolId!, 12_000);

    const [mine] = await seatRequests.listMine(f.riderAId);
    // الرفع هو الشيء الوحيد الذي يطلب من الراكب فعلاً الآن.
    expect(mine.stage).toBe('RAISE_PENDING');
    expect(mine.raise).toEqual({
      oldPricePerSeat: SUGGESTED,
      newPricePerSeat: 12_000,
      respondBy: expect.any(String),
      myResponse: null,
    });

    // ...وبعد الردّ يعود إلى «تأكّدت»، فلا يبقى يطلب شيئاً أجاب عنه.
    await pools.respondToRaise(f.riderAId, a.id, true);
    const [after] = await seatRequests.listMine(f.riderAId);
    expect(after.stage).toBe('CLAIMED');
    void b;
  });

  it('terminal stages read back honestly', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await seatRequests.cancel(f.riderAId, a.id);
    expect((await seatRequests.listMine(f.riderAId))[0].stage).toBe('CANCELLED');
  });

  it('POST returns the SAME shape as GET /mine — one parser, not two', async () => {
    // الإنشاء كان يرجّع صفّ Prisma خام: بلا `stage`، بلا `corridor`، وبنقاط
    // مسطّحة (`pickupLat`…). شكلان لنفس الشيء يعنيان مُحلِّلَين في التطبيق،
    // وحقلاً جديداً يُضاف في أحدهما ويُنسى في الآخر بلا ما يكشفه.
    const created = await seatRequests.create(f.riderAId, {
      corridorId: f.corridorId,
      windowStart: new Date(Date.now() + 3 * HOUR).toISOString(),
      windowEnd: new Date(Date.now() + 6 * HOUR).toISOString(),
      pickup: { lat: 32.0, lng: 44.3, label: 'نقطة الانطلاق' },
      dropoff: { lat: 32.6, lng: 44.0, label: 'نقطة الوصول' },
      seatCount: 1,
    });
    const [listed] = await seatRequests.listMine(f.riderAId);

    expect(created).toEqual(listed);
    // وما يقرأه التطبيق فعلاً موجود، لا مجرّد «متطابقان وفارغان».
    const corridor = await prisma.corridor.findUniqueOrThrow({
      where: { id: f.corridorId },
    });
    expect(created.stage).toBe('WAITING_FOR_RIDERS');
    expect(created.corridor.originCity).toBe(corridor.originCity);
    expect(created.corridor.destCity).toBe(corridor.destCity);
    expect(created.pickup).toEqual({
      lat: 32.0,
      lng: 44.3,
      label: 'نقطة الانطلاق',
    });
    expect(created.pricePerSeat).toBe(SUGGESTED);
  });

  // ── اللوحة ────────────────────────────────────────────────────────────

  it('the board hides pools below the viable minimum, and shows them once reached', async () => {
    await request(f, f.riderAId, 3, 6);
    let board = await pools.board(f.driverUserId);
    expect(board.find((p) => p.corridor.id === f.corridorId)).toBeUndefined();

    await request(f, f.riderBId, 3, 6);
    board = await pools.board(f.driverUserId);
    const row = board.find((p) => p.corridor.id === f.corridorId)!;
    expect(row.totalSeats).toBe(2);
    expect(row.riderCount).toBe(2);
    expect(row.estimatedFare).toBe(SUGGESTED * 2);
  });

  it('the board carries pickup points but NO rider names or phones', async () => {
    await request(f, f.riderAId, 3, 6);
    await request(f, f.riderBId, 3, 6);

    const board = await pools.board(f.driverUserId);
    const row = board.find((p) => p.corridor.id === f.corridorId)!;
    expect(row.stops).toHaveLength(2);
    expect(row.stops[0].pickup.label).toBe('نقطة الانطلاق');

    // نفس قاعدة البحث في Phase 1: بيانات التواصل بعد الالتزام لا قبله.
    const serialised = JSON.stringify(board);
    expect(serialised).not.toContain('+9647');
    expect(serialised).not.toContain('راكب');
  });

  it('an unapproved driver cannot see the board', async () => {
    await prisma.driverProfile.update({
      where: { id: f.driverProfileId },
      data: { status: DriverStatus.PENDING },
    });
    await expect(pools.board(f.driverUserId)).rejects.toBeInstanceOf(ForbiddenException);
  });

  // ── الاستلام ──────────────────────────────────────────────────────────

  it('claiming creates a SYSTEM trip with correct seat accounting and real bookings', async () => {
    const a = await request(f, f.riderAId, 3, 6, 2);
    const b = await request(f, f.riderBId, 4, 7, 1);

    const { trip } = await pools.claim(f.driverUserId, a.poolId!);

    // الرحلة صفٌّ عادي تماماً، بالقيمة التي وُضعت للحظة هذه منذ Phase 1.
    expect(trip.createdBy).toBe(TripCreatedBy.SYSTEM);
    expect(trip.status).toBe(TripStatus.OPEN);
    expect(trip.seatsTotal).toBe(4);
    expect(trip.seatsAvailable).toBe(1); // ٤ − ٣ محجوزة
    expect(trip.pricePerSeat).toBe(SUGGESTED);
    // يغادر في بداية نافذة التجمّع — أبكر وقت يناسب الجميع.
    const pool = await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } });
    expect(trip.departureTime.toISOString()).toBe(pool.windowStart.toISOString());

    const created = await prisma.seatBooking.findMany({ where: { tripId: trip.id } });
    expect(created).toHaveLength(2);
    expect(created.every((x) => x.status === BookingStatus.CONFIRMED)).toBe(true);
    expect(created.reduce((s, x) => s + x.seatCount, 0)).toBe(3);
    // الأجرة = سعر التجمّع × مقاعد الراكب، بنفس صيغة Phase 1.
    const mine = created.find((x) => x.riderId === f.riderAId)!;
    expect(mine.fare).toBe(SUGGESTED * 2);

    // الطلبات صارت مطابَقة وتحمل حجوزاتها.
    for (const id of [a.id, b.id]) {
      const r = await prisma.seatRequest.findUniqueOrThrow({ where: { id } });
      expect(r.status).toBe(SeatRequestStatus.MATCHED);
      expect(r.bookingId).toBeTruthy();
    }
    expect((await notificationsOf(f.riderAId, NotificationType.POOL_CLAIMED))).toHaveLength(1);
    expect((await notificationsOf(f.riderBId, NotificationType.POOL_CLAIMED))).toHaveLength(1);
  });

  it('a pool that fills the car locks the trip immediately', async () => {
    const a = await request(f, f.riderAId, 3, 6, 2);
    await request(f, f.riderBId, 3, 6, 2);
    const { trip } = await pools.claim(f.driverUserId, a.poolId!);
    expect(trip.seatsAvailable).toBe(0);
    expect(trip.status).toBe(TripStatus.LOCKED);
  });

  it('THE RACE: two drivers claim the same pool at once — exactly one wins', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await request(f, f.riderBId, 3, 6);

    const results = await Promise.allSettled([
      pools.claim(f.driverUserId, a.poolId!),
      pools.claim(f.driver2UserId, a.poolId!),
    ]);
    const won = results.filter((r) => r.status === 'fulfilled');
    const lost = results.filter((r) => r.status === 'rejected');
    expect(won).toHaveLength(1);
    expect(lost).toHaveLength(1);

    // وصفٌّ واحد فقط من الرحلات — لا رحلتان لتجمّع واحد، ولا حجوزات مكرّرة.
    const trips = await prisma.trip.findMany({ where: { corridorId: f.corridorId } });
    expect(trips).toHaveLength(1);
    const created = await prisma.seatBooking.findMany({ where: { tripId: trips[0].id } });
    expect(created).toHaveLength(2);

    // **ولماذا خسر، لا أنه خسر فحسب.**
    //
    // بلا هذا التأكيد يمرّ الاختبار لسببٍ خاطئ: فحصُ الجدوى بعده يلتقط
    // الخاسر أيضاً (الطلبات صارت MATCHED فيقرأ صفراً)، فحذفُ حارس
    // `status = FORMING` كان يُبقي كل شيء أخضر — جُرّب فعلاً. والفرق ليس
    // شكلياً: «استلمه سائق آخر» تعني ابحث عن غيره، و«انخفض العدد» تعني
    // انتظر ربما يعود — وهما نصيحتان متعاكستان للسائق.
    const reason = (lost[0] as PromiseRejectedResult).reason as ConflictException;
    expect(reason).toBeInstanceOf(ConflictException);
    // **الرمز** هو ما يفرّع عليه التطبيق، لا النص: أول تحسين صياغة كان سيكسر
    // التفريع بصمت لو طابقنا العربية. والنص يبقى مؤكَّداً أيضاً لأنه ما يقرأه
    // السائق إن لم يعرف التطبيق الرمز.
    const body = reason.getResponse() as { code?: string; message?: string };
    expect(body.code).toBe('POOL_ALREADY_CLAIMED');
    expect(body.message).toContain('استلم سائق آخر');

    const claimedPool = await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } });
    expect(claimedPool.claimedByDriverId).toBe(trips[0].driverId);
    expect(claimedPool.tripId).toBe(trips[0].id);
  });

  it('the Phase 1 seat guarantee still holds on a claimed trip', async () => {
    const a = await request(f, f.riderAId, 3, 6, 2);
    await request(f, f.riderBId, 3, 6, 1);
    const { trip } = await pools.claim(f.driverUserId, a.poolId!);
    expect(trip.seatsAvailable).toBe(1);

    // راكب ثالث يحجز المقعد المتبقّي بالمسار العادي تماماً…
    await bookings.book(f.riderCId, {
      tripId: trip.id,
      pickup: { lat: 32.1, lng: 44.2, label: 'نقطة ثالثة' },
      dropoff: { lat: 32.5, lng: 44.1, label: 'وصول ثالث' },
      seatCount: 1,
    });
    const after = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
    expect(after.seatsAvailable).toBe(0);
    expect(after.status).toBe(TripStatus.LOCKED);

    // …ورابع يُرفض. المخزون لم يُضعَف بأي شيء في Phase 2.
    await expect(
      bookings.book(f.driver2UserId, {
        tripId: trip.id,
        pickup: { lat: 32.1, lng: 44.2, label: 'x' },
        dropoff: { lat: 32.5, lng: 44.1, label: 'y' },
        seatCount: 1,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('refuses a claim when the pool is bigger than the driver’s car', async () => {
    await prisma.vehicle.update({
      where: { driverId: f.driverProfileId },
      data: { seats: 2 },
    });
    const a = await request(f, f.riderAId, 3, 6, 2);
    await request(f, f.riderBId, 3, 6, 1);
    await expect(pools.claim(f.driverUserId, a.poolId!)).rejects.toBeInstanceOf(
      ConflictException,
    );
    // ...ويبقى التجمّع متاحاً لسائق آخر.
    expect((await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } })).status).toBe(
      PoolStatus.FORMING,
    );
  });

  it('a claimed request can no longer be cancelled as a request — it is a booking now', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await request(f, f.riderBId, 3, 6);
    await pools.claim(f.driverUserId, a.poolId!);

    await expect(seatRequests.cancel(f.riderAId, a.id)).rejects.toBeInstanceOf(
      ConflictException,
    );

    // ...والمسار الصحيح هو إلغاء الحجز، بكل قواعده.
    const r = await prisma.seatRequest.findUniqueOrThrow({ where: { id: a.id } });
    const cancelled = await bookings.cancel(f.riderAId, r.bookingId!);
    expect(cancelled.status).toBe(BookingStatus.CANCELLED);
  });

  // ── رفع السعر ─────────────────────────────────────────────────────────

  /**
   * تجمّع مستلَم لم يملأ السيارة — الحالة التي يجوز فيها اقتراح رفع.
   *
   * ٢ + ١ مقعد في سيارة بأربعة: مقعد شاغر يبرّر الرفع، **و**صاحب المقعدين
   * وحده يبلغ الحد المجدي. هذا التوزيع مقصود: مقعد لكلٍّ منهما كان سيجعل أي
   * رفض يُسقط التجمّع، فما كنّا لنستطيع اختبار «قَبِل فسافر» و«رفض فأُطلق»
   * في نفس السيناريو.
   */
  async function claimedUnderfilled() {
    const base = Date.now();
    const a = await request(f, f.riderAId, 3, 6, 2, f.corridorId, base);
    const b = await request(f, f.riderBId, 3, 6, 1, f.corridorId, base);
    const { trip } = await pools.claim(f.driverUserId, a.poolId!);
    return { poolId: a.poolId!, tripId: trip.id, a, b };
  }

  it('a raise above the corridor maximum is refused', async () => {
    const { poolId } = await claimedUnderfilled();
    await expect(
      pools.proposeRaise(f.driverUserId, poolId, MAX_PRICE + 1),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(await prisma.poolRaise.count({ where: { poolId } })).toBe(0);
  });

  it('a raise that is not actually a raise is refused', async () => {
    const { poolId } = await claimedUnderfilled();
    await expect(
      pools.proposeRaise(f.driverUserId, poolId, SUGGESTED),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('a SECOND raise is refused — one per pool, enforced by the unique index', async () => {
    const { poolId } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);
    await expect(
      pools.proposeRaise(f.driverUserId, poolId, 13_000),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(await prisma.poolRaise.count({ where: { poolId } })).toBe(1);
  });

  it('a raise INSIDE the blackout before the window is refused', async () => {
    // نافذة تبدأ بعد ١٠ دقائق — داخل منع الثلاثين دقيقة.
    const created = await seatRequests.create(f.riderAId, {
      corridorId: f.corridorId,
      windowStart: new Date(Date.now() + 10 * MIN).toISOString(),
      windowEnd: new Date(Date.now() + 2 * HOUR).toISOString(),
      pickup: { lat: 32.0, lng: 44.3, label: 'ن' },
      dropoff: { lat: 32.6, lng: 44.0, label: 'و' },
      seatCount: 1,
    });
    const a = await prisma.seatRequest.findUniqueOrThrow({
      where: { id: created.id },
    });
    await seatRequests.create(f.riderBId, {
      corridorId: f.corridorId,
      windowStart: new Date(Date.now() + 10 * MIN).toISOString(),
      windowEnd: new Date(Date.now() + 2 * HOUR).toISOString(),
      pickup: { lat: 32.0, lng: 44.3, label: 'ن' },
      dropoff: { lat: 32.6, lng: 44.0, label: 'و' },
      seatCount: 1,
    });
    await pools.claim(f.driverUserId, a.poolId!);

    // الراكب الذي يرفض يحتاج وقتاً يدبّر فيه بديلاً؛ عشر دقائق ليست وقتاً.
    await expect(
      pools.proposeRaise(f.driverUserId, a.poolId!, 12_000),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('only the claiming driver may propose', async () => {
    const { poolId } = await claimedUnderfilled();
    await expect(
      pools.proposeRaise(f.driver2UserId, poolId, 12_000),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('a raise on a FULL trip is refused — nothing to justify it', async () => {
    const a = await request(f, f.riderAId, 3, 6, 2);
    await request(f, f.riderBId, 3, 6, 2);
    await pools.claim(f.driverUserId, a.poolId!);
    await expect(
      pools.proposeRaise(f.driverUserId, a.poolId!, 12_000),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('accepters travel at the new price; a DECLINER is released with NO no-show record', async () => {
    const { poolId, tripId, a, b } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);

    // صاحب المقعدين يقبل (يبلغ الحد وحده)، وصاحب المقعد يرفض.
    await pools.respondToRaise(f.riderAId, a.id, true);
    await pools.respondToRaise(f.riderBId, b.id, false);

    const raise = await prisma.poolRaise.findUniqueOrThrow({ where: { poolId } });
    expect(raise.resolvedAt).not.toBeNull();
    expect(raise.outcome).toBe(PoolRaiseOutcome.ACCEPTED);

    const trip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
    expect(trip.pricePerSeat).toBe(12_000);
    expect(trip.status).not.toBe(TripStatus.CANCELLED);

    // القابل: أجرته بالسعر الجديد.
    const accepted = await prisma.seatRequest.findUniqueOrThrow({ where: { id: a.id } });
    const acceptedBooking = await prisma.seatBooking.findUniqueOrThrow({
      where: { id: accepted.bookingId! },
    });
    expect(acceptedBooking.fare).toBe(12_000 * 2); // السعر الجديد × مقاعده
    expect(acceptedBooking.status).toBe(BookingStatus.CONFIRMED);

    // الرافض: أُطلق، ومقعده عاد، **وبلا أي واقعة عدم حضور**.
    const declined = await prisma.seatRequest.findUniqueOrThrow({ where: { id: b.id } });
    expect(declined.status).toBe(SeatRequestStatus.DECLINED);
    const declinedBooking = await prisma.seatBooking.findUniqueOrThrow({
      where: { id: declined.bookingId! },
    });
    expect(declinedBooking.status).toBe(BookingStatus.CANCELLED);
    expect(await prisma.noShowRecord.count({ where: { riderId: f.riderBId } })).toBe(0);
    expect((await noShows.blockStateFor(f.riderBId)).countInWindow).toBe(0);

    // حساب المقاعد: ٤ − ٣ محجوزة = ١، ثم عاد مقعد الرافض ⇒ ٢.
    expect(trip.seatsAvailable).toBe(2);
    expect((await notificationsOf(f.riderBId, NotificationType.POOL_EXPIRED))).toHaveLength(1);
  });

  it('under the minimum, the whole pool expires and everyone is released and told', async () => {
    const { poolId, tripId, a, b } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);

    // العكس هذه المرة: صاحب المقعدين يرفض، فلا يبقى إلا مقعد واحد قابل —
    // تحت حدّ المقعدين، فلا رحلة.
    await pools.respondToRaise(f.riderAId, a.id, false);
    await pools.respondToRaise(f.riderBId, b.id, true);

    const raise = await prisma.poolRaise.findUniqueOrThrow({ where: { poolId } });
    expect(raise.outcome).toBe(PoolRaiseOutcome.FAILED);

    const trip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
    expect(trip.status).toBe(TripStatus.CANCELLED);
    expect((await prisma.pool.findUniqueOrThrow({ where: { id: poolId } })).status).toBe(
      PoolStatus.EXPIRED,
    );

    const all = await prisma.seatBooking.findMany({ where: { tripId } });
    expect(all.every((x) => x.status === BookingStatus.CANCELLED)).toBe(true);
    // ولا واقعة عدم حضور على أحد — لا الرافض ولا القابل.
    expect(
      await prisma.noShowRecord.count({
        where: { riderId: { in: [f.riderAId, f.riderBId] } },
      }),
    ).toBe(0);

    // مَن قَبِل كان ينتظر السفر: خبرٌ يكلّفه رحلته، فهو حدث «أُلغيت الرحلة».
    expect((await notificationsOf(f.riderBId, NotificationType.TRIP_CANCELLED))).toHaveLength(1);
    // ومَن رفض خرج بما اختاره — إطلاقٌ بلا التزام.
    expect((await notificationsOf(f.riderAId, NotificationType.POOL_EXPIRED))).toHaveLength(1);
  });

  it('the price NEVER changes again once a raise has resolved', async () => {
    const { poolId, a, b } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);
    await pools.respondToRaise(f.riderAId, a.id, true);
    await pools.respondToRaise(f.riderBId, b.id, true);

    await expect(
      pools.proposeRaise(f.driverUserId, poolId, 15_000),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('a rider cannot answer twice, and cannot answer someone else’s request', async () => {
    const { poolId, a } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);

    await pools.respondToRaise(f.riderAId, a.id, true);
    await expect(pools.respondToRaise(f.riderAId, a.id, false)).rejects.toBeInstanceOf(
      ConflictException,
    );
    await expect(pools.respondToRaise(f.riderCId, a.id, true)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('SILENCE IS A DECLINE: an expired response deadline releases the non-responder', async () => {
    const { poolId, tripId, a, b } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);
    await pools.respondToRaise(f.riderAId, a.id, true);
    // الراكب الثاني لا يردّ أبداً.

    // المهمّة الدورية تحسم بعد المهلة.
    await prisma.poolRaise.update({
      where: { poolId },
      data: { respondBy: new Date(Date.now() - MIN) },
    });
    const resolvedCount = await pools.resolveDueRaises();
    expect(resolvedCount).toBe(1);

    const silent = await prisma.seatRequest.findUniqueOrThrow({ where: { id: b.id } });
    // لم يوافق، فلا يُحمَّل سعراً لم يوافق عليه — والسكوت ليس موافقة.
    expect(silent.status).toBe(SeatRequestStatus.EXPIRED);
    const silentBooking = await prisma.seatBooking.findUniqueOrThrow({
      where: { id: silent.bookingId! },
    });
    expect(silentBooking.status).toBe(BookingStatus.CANCELLED);
    // **وبلا أي أثر سلبي**: صمتٌ على شبكة رديئة ليس تخلّفاً عن موعد.
    expect(await prisma.noShowRecord.count({ where: { riderId: f.riderBId } })).toBe(0);
    expect((await noShows.blockStateFor(f.riderBId)).countInWindow).toBe(0);

    // ومَن قَبِل يسافر: مقاعده وحدها تبلغ الحد، فالرحلة تمضي بالسعر الجديد
    // ومقعد الصامت عاد للبيع. (مسار الرسوب تحت الحد مُغطّى في اختبار آخر.)
    const trip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
    expect(trip.status).toBe(TripStatus.OPEN);
    expect(trip.pricePerSeat).toBe(12_000);
    expect(trip.seatsAvailable).toBe(2);
  });

  it('a resolved raise is never resolved twice', async () => {
    const { poolId, a, b } = await claimedUnderfilled();
    await pools.proposeRaise(f.driverUserId, poolId, 12_000);
    await pools.respondToRaise(f.riderAId, a.id, true);
    await pools.respondToRaise(f.riderBId, b.id, true);

    const before = await prisma.poolRaise.findUniqueOrThrow({ where: { poolId } });
    await pools.resolveRaise(poolId); // المهمّة الدورية تصل متأخرة
    const after = await prisma.poolRaise.findUniqueOrThrow({ where: { poolId } });
    expect(after.resolvedAt?.toISOString()).toBe(before.resolvedAt?.toISOString());
    expect(after.outcome).toBe(PoolRaiseOutcome.ACCEPTED);
  });

  // ── الانتهاء ──────────────────────────────────────────────────────────

  it('an unclaimed pool expires past its window, and its riders are told', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await request(f, f.riderBId, 3, 6);

    await prisma.pool.update({
      where: { id: a.poolId! },
      data: {
        windowStart: new Date(Date.now() - 3 * HOUR),
        windowEnd: new Date(Date.now() - MIN),
      },
    });

    const expired = await pools.expireUnclaimedPools();
    expect(expired).toBe(1);

    expect((await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } })).status).toBe(
      PoolStatus.EXPIRED,
    );
    const members = await prisma.seatRequest.findMany({ where: { poolId: a.poolId! } });
    expect(members.every((m) => m.status === SeatRequestStatus.EXPIRED)).toBe(true);

    // الإخبار هو الجزء المهم — بدونه يقف الراكب ينتظر سيارة لن تأتي.
    for (const id of [f.riderAId, f.riderBId]) {
      expect(await notificationsOf(id, NotificationType.POOL_EXPIRED)).toHaveLength(1);
    }
  });

  it('the sweep never touches a pool a driver claimed', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await request(f, f.riderBId, 3, 6);
    await pools.claim(f.driverUserId, a.poolId!);
    await prisma.pool.update({
      where: { id: a.poolId! },
      data: { windowEnd: new Date(Date.now() - MIN) },
    });

    expect(await pools.expireUnclaimedPools()).toBe(0);
    expect((await prisma.pool.findUniqueOrThrow({ where: { id: a.poolId! } })).status).toBe(
      PoolStatus.CLAIMED,
    );
  });

  it('claiming a pool whose window has shut is refused', async () => {
    const a = await request(f, f.riderAId, 3, 6);
    await request(f, f.riderBId, 3, 6);
    await prisma.pool.update({
      where: { id: a.poolId! },
      data: { windowEnd: new Date(Date.now() - MIN) },
    });
    await expect(pools.claim(f.driverUserId, a.poolId!)).rejects.toBeInstanceOf(
      ConflictException,
    );
  });
});
