import { ConfigService } from '@nestjs/config';
import { DriverStatus, Gender, NotificationType, TripStatus, UserRole } from '@prisma/client';
import { NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { StorageService } from '../storage/storage.service';
import { NotificationService } from '../notification/notification.service';
import { NoShowService } from '../booking/no-show.service';
import { TripService } from '../trip/trip.service';
import { CorridorService } from './corridor.service';
import { RouteRequestService } from './route-request.service';
import { baghdadDayKey } from '../trip/route-request-policy';

/**
 * طلبات المسارات — مقابل قاعدة بيانات حقيقية.
 *
 * الميزة كلها **فان-آوت وعدّ**، وكلاهما لا يُثبَت بـPrisma مُقلَّد: الـmock
 * لا يطبّق `where` أصلاً، فـ«أُشعِر الراكبان اللذان طلبا ولم يُشعَر الثالث»
 * تصير جملةً عن الـmock. وثلاثة من الأخطاء التي تحرسها هذه الملفّات — انتهاء
 * الصلاحية، والختم الذرّي، وراكب بطلبين — كلها شروط `where` أو قيود فهرسة.
 *
 * يحتاج DATABASE_URL. يُشغَّل بـ`npm run test:int` (وCI بعد الترحيل).
 */

const MINUTE = 60_000;
const DAY_MS = 24 * 60 * 60 * 1000;

let prisma: PrismaService;
let trips: TripService;
let routeRequests: RouteRequestService;

interface Fixture {
  tag: string;
  corridorId: string;
  /** ممرّ ثانٍ — يثبت أن الفان-آوت محصور بممرّه. */
  otherCorridorId: string;
  driverProfileId: string;
  driverUserId: string;
  riderAId: string;
  riderBId: string;
  riderCId: string;
}

async function seedFixture(): Promise<Fixture> {
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const [corridor, otherCorridor] = await Promise.all([
    prisma.corridor.create({
      data: {
        originCity: `RR-${tag}-A`,
        destCity: `RR-${tag}-B`,
        suggestedPricePerSeat: 10000,
        minPricePerSeat: 5000,
        maxPricePerSeat: 20000,
        active: true,
      },
    }),
    prisma.corridor.create({
      data: {
        originCity: `RR-${tag}-C`,
        destCity: `RR-${tag}-D`,
        suggestedPricePerSeat: 10000,
        minPricePerSeat: 5000,
        maxPricePerSeat: 20000,
        active: true,
      },
    }),
  ]);

  const driverUser = await prisma.user.create({
    data: {
      phone: `+9647${tag}0000`,
      name: 'سائق الطلبات',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: `RR-${tag}`,
              color: 'أبيض',
              seats: 4,
            },
          },
        },
      },
    },
    include: { driver: true },
  });

  const [riderA, riderB, riderC] = await Promise.all(
    ['1111', '2222', '3333'].map((suffix, i) =>
      prisma.user.create({
        data: {
          phone: `+9647${tag}${suffix}`,
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
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    riderAId: riderA.id,
    riderBId: riderB.id,
    riderCId: riderC.id,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  const userIds = [f.driverUserId, f.riderAId, f.riderBId, f.riderCId];
  const corridorIds = [f.corridorId, f.otherCorridorId];
  await prisma.notification.deleteMany({ where: { userId: { in: userIds } } });
  await prisma.routeRequest.deleteMany({ where: { corridorId: { in: corridorIds } } });
  await prisma.seatBooking.deleteMany({
    where: { trip: { corridorId: { in: corridorIds } } },
  });
  await prisma.trip.deleteMany({ where: { corridorId: { in: corridorIds } } });
  await prisma.vehicle.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.document.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.driverProfile.deleteMany({ where: { id: f.driverProfileId } });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  await prisma.corridor.deleteMany({ where: { id: { in: corridorIds } } });
}

function postTrip(f: Fixture, corridorId = f.corridorId) {
  return trips.createTrip(f.driverUserId, {
    corridorId,
    departureTime: new Date(Date.now() + 180 * MINUTE).toISOString(),
    seatsTotal: 4,
    pricePerSeat: 12000,
  });
}

/** ROUTE_AVAILABLE فقط — بقية الأحداث ليست موضوع هذا الملف. */
async function routeNotifications(userId: string) {
  return prisma.notification.findMany({
    where: { userId, type: NotificationType.ROUTE_AVAILABLE },
    orderBy: { createdAt: 'desc' },
  });
}

/** يزرع طلباً بعمر محدّد — لاختبار النافذة بلا انتظار ٣٠ يوماً. */
function seedRequestAgedDays(
  f: Fixture,
  riderId: string,
  ageDays: number,
  corridorId = f.corridorId,
) {
  const at = new Date(Date.now() - ageDays * DAY_MS);
  return prisma.routeRequest.create({
    data: {
      riderId,
      corridorId,
      requestedDay: baghdadDayKey(at),
      createdAt: at,
    },
  });
}

beforeAll(() => {
  prisma = new PrismaService();
  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  const noShows = new NoShowService(prisma, config);
  routeRequests = new RouteRequestService(prisma, notifications, config);
  trips = new TripService(prisma, drivers, corridors, notifications, noShows, routeRequests);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('route requests (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  // ── تسجيل الطلب ──────────────────────────────────────────────────────

  it('records one request, and a repeat tap the same day returns the SAME row', async () => {
    const first = await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    expect(first.alreadyRequested).toBe(false);

    const second = await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    // إعادة النقر نجاح متكافئ، لا خطأ.
    expect(second.alreadyRequested).toBe(true);
    expect(second.request.id).toBe(first.request.id);

    const rows = await prisma.routeRequest.findMany({
      where: { riderId: f.riderAId, corridorId: f.corridorId },
    });
    expect(rows).toHaveLength(1);
  });

  it('a repeat tap does NOT refresh createdAt — the age runs from the first ask', async () => {
    const first = await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    const second = await routeRequests.record(f.riderAId, {
      corridorId: f.corridorId,
      requestedFor: new Date(Date.now() + 5 * DAY_MS),
    });
    expect(second.request.createdAt.getTime()).toBe(first.request.createdAt.getTime());
    // ولا يلمس requestedFor: أول نيّة هي المسجّلة.
    expect(second.request.requestedFor).toBeNull();
  });

  it('a DIFFERENT Baghdad day is a new signal, so it gets its own row', async () => {
    const today = new Date('2026-08-09T12:00:00.000Z');
    const tomorrow = new Date('2026-08-10T12:00:00.000Z');

    const a = await routeRequests.record(f.riderAId, { corridorId: f.corridorId }, today);
    const b = await routeRequests.record(f.riderAId, { corridorId: f.corridorId }, tomorrow);

    expect(a.alreadyRequested).toBe(false);
    expect(b.alreadyRequested).toBe(false);
    expect(b.request.id).not.toBe(a.request.id);
  });

  it('two riders asking for the same corridor on the same day are two rows', async () => {
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    await routeRequests.record(f.riderBId, { corridorId: f.corridorId });
    const rows = await prisma.routeRequest.findMany({ where: { corridorId: f.corridorId } });
    expect(rows).toHaveLength(2);
  });

  it('refuses an unknown corridor with 404 rather than writing an orphan row', async () => {
    await expect(
      routeRequests.record(f.riderAId, { corridorId: 'no-such-corridor' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('stores requestedFor when the rider had a date in the search form', async () => {
    const when = new Date(Date.now() + 2 * DAY_MS);
    const { request } = await routeRequests.record(f.riderAId, {
      corridorId: f.corridorId,
      requestedFor: when,
    });
    expect(request.requestedFor?.getTime()).toBe(when.getTime());
  });

  // ── الفان-آوت عند إعلان رحلة ─────────────────────────────────────────

  it('a posted trip notifies EXACTLY the riders who asked — and marks them fulfilled', async () => {
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    await routeRequests.record(f.riderBId, { corridorId: f.corridorId });
    // راكب ثالث لم يطلب هذا المسار، بل الآخر.
    await routeRequests.record(f.riderCId, { corridorId: f.otherCorridorId });

    const trip = await postTrip(f);

    expect(await routeNotifications(f.riderAId)).toHaveLength(1);
    expect(await routeNotifications(f.riderBId)).toHaveLength(1);
    expect(await routeNotifications(f.riderCId)).toHaveLength(0);
    // والسائق ليس طرفاً في هذا الحدث.
    expect(await routeNotifications(f.driverUserId)).toHaveLength(0);

    const [notification] = await routeNotifications(f.riderAId);
    expect(notification.type).toBe(NotificationType.ROUTE_AVAILABLE);
    expect(notification.tripId).toBe(trip.id);
    expect(notification.title).toBe('توفّرت رحلة على مسار طلبته');
    // النصّ يحمل اسم المسار، وهو ما يجعله مفهوماً بلا فتح التطبيق.
    expect(notification.body).toContain('RR-');
    expect(notification.body).toContain('إلى');

    const claimed = await prisma.routeRequest.findMany({
      where: { corridorId: f.corridorId },
    });
    expect(claimed).toHaveLength(2);
    for (const row of claimed) {
      expect(row.fulfilledAt).not.toBeNull();
      expect(row.fulfilledByTripId).toBe(trip.id);
    }

    // طلب الممر الآخر لم يُمَسّ.
    const untouched = await prisma.routeRequest.findFirst({
      where: { corridorId: f.otherCorridorId },
    });
    expect(untouched?.fulfilledAt).toBeNull();
  });

  it('a SECOND trip on the same corridor notifies nobody again', async () => {
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });

    await postTrip(f);
    expect(await routeNotifications(f.riderAId)).toHaveLength(1);

    // نفس الراكب، نفس الممر، رحلة ثانية: الطلب استُهلك.
    await postTrip(f);
    expect(await routeNotifications(f.riderAId)).toHaveLength(1);
  });

  it('ONE rider with TWO outstanding requests on one corridor is notified ONCE', async () => {
    // الفهرس الفريد يمنع التكرار داخل اليوم فقط — سؤالان في يومين مختلفين
    // صفّان مشروعان، وإشعاران عن رحلة واحدة يقرآن كعطل.
    await seedRequestAgedDays(f, f.riderAId, 3);
    await seedRequestAgedDays(f, f.riderAId, 1);
    expect(
      await prisma.routeRequest.count({ where: { riderId: f.riderAId, fulfilledAt: null } }),
    ).toBe(2);

    const trip = await postTrip(f);

    expect(await routeNotifications(f.riderAId)).toHaveLength(1);
    // ومع ذلك يُختم الصفّان، وإلا بقي أحدهما يعِد بإشعار لن يأتي.
    const rows = await prisma.routeRequest.findMany({ where: { riderId: f.riderAId } });
    expect(rows).toHaveLength(2);
    expect(rows.every((r) => r.fulfilledByTripId === trip.id)).toBe(true);
  });

  it('an EXPIRED request generates no notification, and stays unfulfilled', async () => {
    await seedRequestAgedDays(f, f.riderAId, 31); // خارج نافذة الـ٣٠ يوماً
    await seedRequestAgedDays(f, f.riderBId, 29); // داخلها

    await postTrip(f);

    expect(await routeNotifications(f.riderAId)).toHaveLength(0);
    expect(await routeNotifications(f.riderBId)).toHaveLength(1);

    const stale = await prisma.routeRequest.findFirst({ where: { riderId: f.riderAId } });
    // غير محقّق عمداً: «محقّق» تعني «أُشعِر صاحبه»، ووسمه كذباً في السجل.
    expect(stale?.fulfilledAt).toBeNull();
  });

  it('a trip on a corridor nobody asked about notifies nobody and fails nothing', async () => {
    const trip = await postTrip(f);
    expect(trip.id).toBeTruthy();
    expect(await routeNotifications(f.riderAId)).toHaveLength(0);
  });

  // ── تجميع اللوحة ─────────────────────────────────────────────────────

  it('ranks corridors by demand, and counts RIDERS as well as requests', async () => {
    // الممر الأول: راكبان، ثلاثة طلبات (أحدهما سأل مرتين في يومين).
    await seedRequestAgedDays(f, f.riderAId, 2);
    await seedRequestAgedDays(f, f.riderAId, 1);
    await routeRequests.record(f.riderBId, { corridorId: f.corridorId });
    // الممر الثاني: راكب واحد، طلب واحد.
    await routeRequests.record(f.riderCId, { corridorId: f.otherCorridorId });

    const rows = await routeRequests.demand();
    const first = rows.find((r) => r.corridorId === f.corridorId)!;
    const second = rows.find((r) => r.corridorId === f.otherCorridorId)!;

    expect(first.requestCount).toBe(3);
    // ثلاثة طلبات، راكبان. الفرق هو ما يمنع قراءة إصرار شخص واحد كطلبِ سوق.
    expect(first.riderCount).toBe(2);
    expect(second.requestCount).toBe(1);
    expect(second.riderCount).toBe(1);

    // الأعلى طلباً أولاً.
    expect(rows.indexOf(first)).toBeLessThan(rows.indexOf(second));
  });

  it('counts live supply by STATUS, so a departNow trip counts as served', async () => {
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });

    // «الآن»: وقت مغادرتها يمضي لحظة إعلانها. أي `departureTime > now` مكتوب
    // باليد كان سيعدّ هذا الممر بلا عرض بينما سيارة على وشك الانطلاق فيه.
    await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });

    // الطلب استُهلك بالإعلان نفسه، فنزرع طلباً جديداً لنرى صفّ الممر.
    await routeRequests.record(f.riderBId, { corridorId: f.corridorId });

    const rows = await routeRequests.demand();
    const row = rows.find((r) => r.corridorId === f.corridorId)!;
    expect(row.activeTrips).toBe(1);
  });

  it('unservedOnly isolates demand with NO supply — the actionable list', async () => {
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    await routeRequests.record(f.riderCId, { corridorId: f.otherCorridorId });

    // عرض على الممر الأول فقط. (الإعلان يستهلك طلب riderA، فنعيد الطلب بعده.)
    await postTrip(f, f.corridorId);
    await routeRequests.record(f.riderBId, { corridorId: f.corridorId });

    const all = await routeRequests.demand();
    expect(all.map((r) => r.corridorId)).toEqual(
      expect.arrayContaining([f.corridorId, f.otherCorridorId]),
    );

    const unserved = await routeRequests.demand({ unservedOnly: true });
    const ids = unserved.map((r) => r.corridorId);
    expect(ids).toContain(f.otherCorridorId);
    expect(ids).not.toContain(f.corridorId);
  });

  it('a cancelled trip stops counting as supply', async () => {
    const trip = await postTrip(f);
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });

    let row = (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId)!;
    expect(row.activeTrips).toBe(1);

    await trips.cancelTrip(f.driverUserId, trip.id);

    row = (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId)!;
    expect(row.activeTrips).toBe(0);
    // ...ويعود الممر إلى القائمة القابلة للتنفيذ.
    const unserved = await routeRequests.demand({ unservedOnly: true });
    expect(unserved.map((r) => r.corridorId)).toContain(f.corridorId);
  });

  it('a fulfilled request drops out of the aggregate — it is answered, not pending', async () => {
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    expect(
      (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId),
    ).toBeDefined();

    await postTrip(f);

    expect(
      (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId),
    ).toBeUndefined();
  });

  it('an EXPIRED request drops out of the aggregate too — same window as the fan-out', async () => {
    // لو اختلفت النافذتان لظهر للأدمن طلبٌ لن يُشعَر صاحبه أبداً.
    await seedRequestAgedDays(f, f.riderAId, 31);
    expect(
      (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId),
    ).toBeUndefined();
  });

  it('reports whether the corridor itself is switched off', async () => {
    await prisma.corridor.update({
      where: { id: f.corridorId },
      data: { active: false },
    });
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });

    const row = (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId)!;
    // طلبٌ على ممرّ عطّله الأدمن معلومة مفيدة، لا خطأ: ربما عُطّل قبل أن
    // يظهر الطلب. الشاشة تعرضه ولا تخفيه.
    expect(row.corridorActive).toBe(false);
    expect(row.requestCount).toBe(1);
  });

  it('a trip that never left OPEN still counts as supply', async () => {
    // حارس ضد تضييق العدّ لاحقاً إلى EN_ROUTE وحدها: رحلة OPEN هي بالضبط
    // ما يستطيع الراكب حجزه، وهي العرض الذي يسأل عنه الأدمن.
    await postTrip(f);
    await routeRequests.record(f.riderAId, { corridorId: f.corridorId });
    const row = (await routeRequests.demand()).find((r) => r.corridorId === f.corridorId)!;
    expect(row.activeTrips).toBe(1);

    const trip = await prisma.trip.findFirst({ where: { corridorId: f.corridorId } });
    expect(trip?.status).toBe(TripStatus.OPEN);
  });
});
