import { BookingStatus, DriverStatus, Gender, TripStatus, UserRole } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { RouteRequestService } from '../corridor/route-request.service';
import { StorageService } from '../storage/storage.service';
import { NotificationService } from '../notification/notification.service';
import { TripService } from '../trip/trip.service';
import { BookingService } from './booking.service';
import { NoShowService } from './no-show.service';

/**
 * عواقب عدم الحضور — ضد قاعدة بيانات حقيقية.
 *
 * لماذا تكامل لا وحدات: كل شيء هنا **تفاعل**. النافذة المتدحرجة تُقاس على صفوف
 * كتبتها معاملة أخرى، والإيقاف يقرأها مسار ثالث (`POST /bookings`)، والتظلّم
 * يعدّلها مسار رابع (الأدمن). اختبار وحدة لأي منها ينجح وكلها مفصولة — وهذا
 * بالضبط ما حصل مع كل علّة سابقة في هذا الريبو.
 *
 * الوقائع تُزرع بتواريخ ماضية مباشرةً في الجدول: انتظار ٣٠ يوماً غير وارد،
 * ومحاكاة الساعة تختبر الوهم لا القاعدة.
 *
 * Requires DATABASE_URL. Run with `npm run test:int` (CI does, after migrate).
 */

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;

let prisma: PrismaService;
let trips: TripService;
let bookings: BookingService;
let noShows: NoShowService;

interface Fixture {
  corridorId: string;
  driverProfileId: string;
  driverUserId: string;
  riderId: string;
  otherRiderId: string;
}

async function seedFixture(): Promise<Fixture> {
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const corridor = await prisma.corridor.create({
    data: {
      originCity: `NS-${tag}-A`,
      destCity: `NS-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+9649${tag}0000`,
      name: 'سائق الغياب',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: { make: 'Toyota', model: 'Corolla', plate: `NS-${tag}`, color: 'أبيض', seats: 4 },
          },
        },
      },
    },
    include: { driver: true },
  });

  const [rider, otherRider] = await Promise.all([
    prisma.user.create({
      data: {
        phone: `+9649${tag}1111`,
        name: 'راكب متغيّب',
        gender: Gender.MALE,
        roles: [UserRole.RIDER],
      },
    }),
    prisma.user.create({
      data: {
        phone: `+9649${tag}2222`,
        name: 'راكب منضبط',
        gender: Gender.MALE,
        roles: [UserRole.RIDER],
      },
    }),
  ]);

  return {
    corridorId: corridor.id,
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    riderId: rider.id,
    otherRiderId: otherRider.id,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  const userIds = [f.driverUserId, f.riderId, f.otherRiderId];
  await prisma.noShowRecord.deleteMany({ where: { riderId: { in: userIds } } });
  await prisma.rating.deleteMany({ where: { fromUserId: { in: userIds } } });
  await prisma.notification.deleteMany({ where: { userId: { in: userIds } } });
  await prisma.earningsRecord.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.seatBooking.deleteMany({ where: { trip: { corridorId: f.corridorId } } });
  await prisma.trip.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.vehicle.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.document.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.driverProfile.deleteMany({ where: { id: f.driverProfileId } });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  await prisma.corridor.deleteMany({ where: { id: f.corridorId } });
}

function postTrip(f: Fixture, seatsTotal = 4) {
  return trips.createTrip(f.driverUserId, {
    corridorId: f.corridorId,
    departureTime: new Date(Date.now() + 180 * MINUTE).toISOString(),
    seatsTotal,
    pricePerSeat: 12000,
  });
}

function book(riderId: string, tripId: string, seatCount = 1) {
  return bookings.book(riderId, {
    tripId,
    pickup: { lat: 32.0, lng: 44.3, label: 'نقطة الانطلاق' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'نقطة الوصول' },
    seatCount,
  });
}

/**
 * A no-show that happened `daysAgo` days ago.
 *
 * Written straight to the table because the policy is about ELAPSED TIME, and
 * neither waiting 30 days nor faking the clock tests the rolling window — the
 * window is a query, and a query can only be tested with real timestamps.
 */
function seedNoShow(f: Fixture, riderId: string, daysAgo: number, tag = 'x') {
  return prisma.noShowRecord.create({
    data: {
      riderId,
      tripId: `seed-trip-${tag}-${daysAgo}-${Math.random().toString(36).slice(2, 8)}`,
      bookingId: `seed-bk-${tag}-${daysAgo}-${Math.random().toString(36).slice(2, 8)}`,
      seatCount: 1,
      createdAt: new Date(Date.now() - daysAgo * DAY),
    },
  });
}

/** The whole flow that produces a REAL no-show: post → book → start → mark. */
async function realNoShow(f: Fixture, riderId: string) {
  const trip = await postTrip(f);
  const booking = await book(riderId, trip.id);
  await trips.start(f.driverUserId, trip.id);
  await bookings.noShow(f.driverUserId, booking.id);
  return { trip, booking };
}

beforeAll(async () => {
  prisma = new PrismaService();
  await prisma.$connect();

  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  noShows = new NoShowService(prisma, config);
  const routeRequests = new RouteRequestService(prisma, notifications, config);
  trips = new TripService(prisma, drivers, corridors, notifications, noShows, routeRequests);
  bookings = new BookingService(prisma, drivers, notifications, noShows);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('a no-show can only be recorded on a trip that actually ran', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('refuses on an OPEN trip, and writes no record', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);

    await expect(bookings.noShow(f.driverUserId, booking.id)).rejects.toThrow(
      /يجب أن تكون الرحلة جارية/,
    );

    // The important half: no penalty was recorded for a trip nobody drove.
    expect(await prisma.noShowRecord.count({ where: { riderId: f.riderId } })).toBe(0);
    const after = await prisma.seatBooking.findUniqueOrThrow({ where: { id: booking.id } });
    expect(after.status).toBe(BookingStatus.CONFIRMED);
  });

  it('refuses on a LOCKED trip the driver never started', async () => {
    // The exact trap: the window shuts, the trip locks, the driver never turns
    // up — and the rider must not be penalised for that.
    const trip = await postTrip(f, 1);
    const booking = await book(f.riderId, trip.id, 1);
    expect((await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } })).status).toBe(
      TripStatus.LOCKED,
    );

    await expect(bookings.noShow(f.driverUserId, booking.id)).rejects.toThrow(
      /يجب أن تكون الرحلة جارية/,
    );
    expect(await prisma.noShowRecord.count({ where: { riderId: f.riderId } })).toBe(0);
  });

  it('records exactly one row once the trip is EN_ROUTE', async () => {
    const { booking } = await realNoShow(f, f.riderId);

    const rows = await prisma.noShowRecord.findMany({ where: { riderId: f.riderId } });
    expect(rows).toHaveLength(1);
    expect(rows[0].bookingId).toBe(booking.id);
    expect(rows[0].voidedAt).toBeNull();
    // The seat is NOT returned — that is the driver's loss this whole policy is about.
    const trip = await prisma.trip.findUniqueOrThrow({ where: { id: rows[0].tripId } });
    expect(trip.seatsAvailable).toBe(3);
  });
});

describe('the rolling window blocks, then lets go', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('3 no-shows inside 30 days refuse the 4th booking, naming the reason and the date', async () => {
    await seedNoShow(f, f.riderId, 20, 'a');
    await seedNoShow(f, f.riderId, 10, 'b');
    await seedNoShow(f, f.riderId, 1, 'c');

    const trip = await postTrip(f);
    const err = await book(f.riderId, trip.id).catch((e) => e);

    expect(err).toBeInstanceOf(ForbiddenException);
    const body = err.getResponse();
    expect(body.code).toBe('RIDER_BLOCKED_NO_SHOW');
    expect(body.message).toMatch(/عدم الحضور/);
    expect(body.noShowCount).toBe(3);
    expect(body.threshold).toBe(3);
    // The rider is told WHEN it lifts — 7 days after the most recent one.
    const until = new Date(body.blockedUntil);
    const expected = Date.now() + 6 * DAY; // last no-show was 1 day ago
    expect(Math.abs(until.getTime() - expected)).toBeLessThan(2 * MINUTE);

    // Refused before the seat transaction: the trip is untouched.
    expect((await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } })).seatsAvailable).toBe(4);
  });

  it('2 inside the window is not enough', async () => {
    await seedNoShow(f, f.riderId, 10, 'a');
    await seedNoShow(f, f.riderId, 2, 'b');
    const trip = await postTrip(f);
    await expect(book(f.riderId, trip.id)).resolves.toBeDefined();
  });

  it('3 spread wider than the window is not enough — it is a rate, not a lifetime total', async () => {
    await seedNoShow(f, f.riderId, 100, 'a');
    await seedNoShow(f, f.riderId, 60, 'b');
    await seedNoShow(f, f.riderId, 2, 'c');
    const trip = await postTrip(f);
    await expect(book(f.riderId, trip.id)).resolves.toBeDefined();
  });

  it('after the cooling-off period the rider can book again, with the records still there', async () => {
    // Three inside the 30-day window, but the most recent was 8 days ago — so
    // the 7-day block has run its course.
    await seedNoShow(f, f.riderId, 25, 'a');
    await seedNoShow(f, f.riderId, 15, 'b');
    await seedNoShow(f, f.riderId, 8, 'c');

    const state = await noShows.blockStateFor(f.riderId);
    expect(state.countInWindow).toBe(3);
    expect(state.blocked).toBe(false);

    const trip = await postTrip(f);
    await expect(book(f.riderId, trip.id)).resolves.toBeDefined();
    // Serving the block does not erase the history.
    expect(await prisma.noShowRecord.count({ where: { riderId: f.riderId } })).toBe(3);
  });

  it('blocks the rider who earned it and nobody else', async () => {
    await seedNoShow(f, f.riderId, 5, 'a');
    await seedNoShow(f, f.riderId, 4, 'b');
    await seedNoShow(f, f.riderId, 3, 'c');

    const trip = await postTrip(f);
    await expect(book(f.riderId, trip.id)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(book(f.otherRiderId, trip.id)).resolves.toBeDefined();
  });
});

describe('a block prevents new bookings and touches nothing else', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('leaves an existing CONFIRMED booking alone — and the rider can still cancel it', async () => {
    // Book FIRST, then earn the block. The seat the rider already holds is
    // theirs: cancelling it as a punishment would take a paying passenger off
    // the driver's trip too, which is the opposite of protecting drivers.
    const held = await postTrip(f);
    const existing = await book(f.riderId, held.id, 2);

    await seedNoShow(f, f.riderId, 3, 'a');
    await seedNoShow(f, f.riderId, 2, 'b');
    await seedNoShow(f, f.riderId, 1, 'c');
    expect((await noShows.blockStateFor(f.riderId)).blocked).toBe(true);

    const stillThere = await prisma.seatBooking.findUniqueOrThrow({ where: { id: existing.id } });
    expect(stillThere.status).toBe(BookingStatus.CONFIRMED);

    // A NEW booking is refused…
    const other = await postTrip(f);
    await expect(book(f.riderId, other.id)).rejects.toBeInstanceOf(ForbiddenException);

    // …while the seat they already hold stays fully under their control.
    await expect(bookings.cancel(f.riderId, existing.id)).resolves.toBeDefined();
    expect((await prisma.trip.findUniqueOrThrow({ where: { id: held.id } })).seatsAvailable).toBe(4);
  });
});

describe('the appeal path restores the rider', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('voiding ONE no-show drops the rider under the threshold and booking works again', async () => {
    await seedNoShow(f, f.riderId, 5, 'a');
    await seedNoShow(f, f.riderId, 4, 'b');
    const third = await seedNoShow(f, f.riderId, 1, 'c');

    const blocked = await postTrip(f);
    await expect(book(f.riderId, blocked.id)).rejects.toBeInstanceOf(ForbiddenException);

    const res = await noShows.void(third.id, 'admin-1', 'ظرف طارئ — مستشفى');
    expect(res.voided).toBe(true);

    // The row survives with its reason: this is a record, not a delete.
    const row = await prisma.noShowRecord.findUniqueOrThrow({ where: { id: third.id } });
    expect(row.voidedAt).not.toBeNull();
    expect(row.voidedBy).toBe('admin-1');
    expect(row.voidReason).toBe('ظرف طارئ — مستشفى');

    expect((await noShows.blockStateFor(f.riderId)).countInWindow).toBe(2);
    await expect(book(f.riderId, blocked.id)).resolves.toBeDefined();
  });

  it('lifting a block voids every live record in the window, in one action', async () => {
    await seedNoShow(f, f.riderId, 6, 'a');
    await seedNoShow(f, f.riderId, 4, 'b');
    await seedNoShow(f, f.riderId, 2, 'c');
    expect((await noShows.blockStateFor(f.riderId)).blocked).toBe(true);

    const { voided } = await noShows.liftBlock(f.riderId, 'admin-2', 'مراجعة إدارية');
    expect(voided).toBe(3);

    const state = await noShows.blockStateFor(f.riderId);
    expect(state.blocked).toBe(false);
    expect(state.countInWindow).toBe(0);

    const trip = await postTrip(f);
    await expect(book(f.riderId, trip.id)).resolves.toBeDefined();
  });

  it('voiding the same record twice is a no-op, not a second void', async () => {
    const one = await seedNoShow(f, f.riderId, 1, 'a');
    expect((await noShows.void(one.id, 'admin-1', 'سبب')).voided).toBe(true);
    expect((await noShows.void(one.id, 'admin-2', 'مرة أخرى')).voided).toBe(false);
    const row = await prisma.noShowRecord.findUniqueOrThrow({ where: { id: one.id } });
    expect(row.voidedBy).toBe('admin-1'); // the first decision stands
  });

  it('a blocked rider is findable in the admin list, with the date and the count', async () => {
    await seedNoShow(f, f.riderId, 3, 'a');
    await seedNoShow(f, f.riderId, 2, 'b');
    await seedNoShow(f, f.riderId, 1, 'c');

    const rows = await noShows.blockedRiders();
    const mine = rows.find((r) => r.rider?.id === f.riderId);
    expect(mine).toBeDefined();
    expect(mine!.state.countInWindow).toBe(3);
    expect(mine!.state.blockedUntil).toBeInstanceOf(Date);
    // The well-behaved rider is not in the list.
    expect(rows.some((r) => r.rider?.id === f.otherRiderId)).toBe(false);
  });
});

describe('the driver can see the record of who they are carrying', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('puts a per-rider count on the trip bookings list, and 0 for the clean rider', async () => {
    await seedNoShow(f, f.riderId, 5, 'a');
    await seedNoShow(f, f.riderId, 3, 'b');

    const trip = await postTrip(f);
    await book(f.riderId, trip.id);
    await book(f.otherRiderId, trip.id);

    const rows = await trips.listBookings(f.driverUserId, trip.id);
    expect(rows.find((r) => r.riderId === f.riderId)!.riderNoShowCount).toBe(2);
    expect(rows.find((r) => r.riderId === f.otherRiderId)!.riderNoShowCount).toBe(0);
  });

  it('a voided record stops counting for the driver too', async () => {
    const one = await seedNoShow(f, f.riderId, 5, 'a');
    await seedNoShow(f, f.riderId, 3, 'b');
    await noShows.void(one.id, 'admin-1', 'عذر مقبول');

    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const rows = await trips.listBookings(f.driverUserId, trip.id);
    expect(rows.find((r) => r.riderId === f.riderId)!.riderNoShowCount).toBe(1);
  });
});

describe('the rider is never trapped into a no-show', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('cancels a departNow booking after the window has shut and the trip has LOCKED', async () => {
    // The exact case the policy would otherwise punish: a «الآن» trip whose
    // 30-minute window closed while the driver never started. Under the old
    // 15-minute cutoff this threw, leaving the rider bound to a trip they could
    // not leave — and markable as a no-show the moment the driver did start.
    const trip = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    const booking = await book(f.riderId, trip.id, 2);

    // Push the trip past its window and lock it, exactly as the expiry sweep does.
    await prisma.trip.update({
      where: { id: trip.id },
      data: { departureTime: new Date(Date.now() - 45 * MINUTE), status: TripStatus.LOCKED },
    });

    await expect(bookings.cancel(f.riderId, booking.id)).resolves.toBeDefined();
    const after = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
    expect(after.seatsAvailable).toBe(4); // the seats went back to the driver
  });

  it('cancels a scheduled booking five minutes before departure', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);
    await prisma.trip.update({
      where: { id: trip.id },
      data: { departureTime: new Date(Date.now() + 5 * MINUTE) },
    });

    await expect(bookings.cancel(f.riderId, booking.id)).resolves.toBeDefined();
  });

  it('but not once the trip is EN_ROUTE — by then the seat really is gone', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id);

    await expect(bookings.cancel(f.riderId, booking.id)).rejects.toThrow(/بعد بدء الرحلة/);
  });
});
