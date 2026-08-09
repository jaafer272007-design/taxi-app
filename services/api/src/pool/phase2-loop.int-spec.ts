import { ConfigService } from '@nestjs/config';
import {
  BookingStatus,
  DriverStatus,
  Gender,
  NotificationType,
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
import { CorridorService } from '../corridor/corridor.service';
import { RouteRequestService } from '../corridor/route-request.service';
import { TripService } from '../trip/trip.service';
import { EarningsService } from '../earnings/earnings.service';
import { RatingService } from '../rating/rating.service';
import { PoolService } from './pool.service';
import { SeatRequestService } from './seat-request.service';

/**
 * **The whole Phase 2 loop, in one piece, against a real database.**
 *
 * Riders ask → a pool forms → a driver claims → the trip runs → it completes →
 * the money is right. Every stage of that has been tested on its own; this is
 * the first test that walks the join between them, and the joins are where this
 * design either holds or doesn't.
 *
 * The claim is the seam: it turns pool rows into a `Trip` with
 * `createdBy = SYSTEM` and ordinary `SeatBooking`s, and **everything after it
 * is Phase 1 code that has never seen a pool**. So this spec deliberately calls
 * the ordinary services — `TripService.start`, `BookingService.onboard`,
 * `TripService.complete`, `EarningsService.getEarnings`, `RatingService.create`
 * — rather than anything pool-shaped. If any of them had quietly assumed
 * `createdBy = DRIVER`, it would fail here and nowhere else.
 *
 * Needs DATABASE_URL. Run with `npm run test:int`.
 */

const MIN = 60_000;
const HOUR = 60 * MIN;

const SUGGESTED = 10_000;
const MAX_PRICE = 20_000;

let prisma: PrismaService;
let seatRequests: SeatRequestService;
let pools: PoolService;
let bookings: BookingService;
let trips: TripService;
let earnings: EarningsService;
let ratings: RatingService;

interface Fixture {
  tag: string;
  corridorId: string;
  driverUserId: string;
  driverProfileId: string;
  riderAId: string;
  riderBId: string;
  riderCId: string;
}

async function seedFixture(): Promise<Fixture> {
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const corridor = await prisma.corridor.create({
    data: {
      originCity: `LOOP-${tag}-A`,
      destCity: `LOOP-${tag}-B`,
      suggestedPricePerSeat: SUGGESTED,
      minPricePerSeat: 5_000,
      maxPricePerSeat: MAX_PRICE,
      active: true,
    },
  });

  const driver = await prisma.user.create({
    data: {
      phone: `+9647${tag}0001`,
      name: 'سائق الحلقة',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: `LOOP-${tag}`,
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
    ['1111', '2222', '3333'].map((s, i) =>
      prisma.user.create({
        data: {
          phone: `+9647${tag}${s}`,
          name: `راكب ${i + 1}`,
          gender: Gender.MALE,
          roles: [UserRole.RIDER],
        },
      }),
    ),
  );

  return {
    tag,
    corridorId: corridor.id,
    driverUserId: driver.id,
    driverProfileId: driver.driver!.id,
    riderAId: riderA.id,
    riderBId: riderB.id,
    riderCId: riderC.id,
  };
}

async function dropFixture(f: Fixture) {
  const userIds = [f.driverUserId, f.riderAId, f.riderBId, f.riderCId];
  const tripIds = (
    await prisma.trip.findMany({
      where: { corridorId: f.corridorId },
      select: { id: true },
    })
  ).map((t) => t.id);

  await prisma.rating.deleteMany({ where: { tripId: { in: tripIds } } });
  await prisma.notification.deleteMany({ where: { userId: { in: userIds } } });
  await prisma.noShowRecord.deleteMany({ where: { riderId: { in: userIds } } });
  await prisma.earningsRecord.deleteMany({
    where: { driverId: f.driverProfileId },
  });
  await prisma.poolRaise.deleteMany({
    where: { pool: { corridorId: f.corridorId } },
  });
  await prisma.seatRequest.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.pool.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.seatBooking.deleteMany({ where: { tripId: { in: tripIds } } });
  await prisma.trip.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.vehicle.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.document.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.driverProfile.deleteMany({ where: { id: f.driverProfileId } });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  await prisma.corridor.deleteMany({ where: { id: f.corridorId } });
}

/** A seat request with a window relative to `base`. */
function request(
  f: Fixture,
  riderId: string,
  fromHours: number,
  toHours: number,
  seatCount: number,
  base: number,
) {
  return seatRequests.create(riderId, {
    corridorId: f.corridorId,
    windowStart: new Date(base + fromHours * HOUR).toISOString(),
    windowEnd: new Date(base + toHours * HOUR).toISOString(),
    pickup: { lat: 32.0, lng: 44.3, label: 'نقطة الانطلاق' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'نقطة الوصول' },
    seatCount,
  });
}

beforeAll(() => {
  prisma = new PrismaService();
  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  const noShows = new NoShowService(prisma, config);
  const corridors = new CorridorService(prisma);
  const routeRequests = new RouteRequestService(prisma, notifications, config);

  seatRequests = new SeatRequestService(prisma, noShows, config);
  pools = new PoolService(prisma, drivers, notifications, config);
  bookings = new BookingService(prisma, drivers, notifications, noShows);
  trips = new TripService(
    prisma,
    drivers,
    corridors,
    notifications,
    noShows,
    routeRequests,
  );
  earnings = new EarningsService(prisma, drivers);
  ratings = new RatingService(prisma);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('Phase 2 — the whole loop (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('rider requests → pool forms → driver claims → trip runs → completes → earnings are right', async () => {
    const base = Date.now();

    // ── 1. Two riders ask for seats in overlapping windows ───────────────
    //
    // One seat then two: the first request alone is under POOL_MIN_SEATS, so
    // this also walks the stage the rider actually sees change.
    const a = await request(f, f.riderAId, 3, 6, 1, base);
    const b = await request(f, f.riderBId, 4, 7, 2, base);

    const poolRow = await prisma.seatRequest.findUniqueOrThrow({
      where: { id: a.id },
    });
    const poolId = poolRow.poolId!;
    expect(
      (await prisma.seatRequest.findUniqueOrThrow({ where: { id: b.id } }))
        .poolId,
    ).toBe(poolId);
    expect(a.stage).toBe('WAITING_FOR_RIDERS');

    // Three seats is viable, so the rider is now waiting for a DRIVER — the
    // distinction the app shows and never re-derives.
    expect((await seatRequests.listMine(f.riderAId))[0].stage).toBe(
      'WAITING_FOR_DRIVER',
    );

    // ── 2. It reaches the driver's board ─────────────────────────────────
    const board = await pools.board(f.driverUserId);
    const row = board.find((p) => p.id === poolId);
    expect(row).toBeDefined();
    expect(row!.totalSeats).toBe(3);
    expect(row!.riderCount).toBe(2);
    expect(row!.pricePerSeat).toBe(SUGGESTED);
    expect(row!.estimatedFare).toBe(SUGGESTED * 3);
    // Points, but no identities: the board is browsed before any commitment.
    expect(row!.stops).toHaveLength(2);
    expect(JSON.stringify(row)).not.toContain(f.riderAId);

    // ── 3. The driver claims it ──────────────────────────────────────────
    const { trip } = await pools.claim(f.driverUserId, poolId);
    expect(trip.createdBy).toBe(TripCreatedBy.SYSTEM);
    expect(trip.pricePerSeat).toBe(SUGGESTED);
    expect(trip.seatsTotal).toBe(4);
    expect(trip.seatsAvailable).toBe(1);
    expect(trip.status).toBe(TripStatus.OPEN);

    // Both riders now hold ordinary bookings, and both were told.
    const claimed = await prisma.seatBooking.findMany({
      where: { tripId: trip.id },
    });
    expect(claimed).toHaveLength(2);
    // Looked up by rider, never by list position: `findMany` has no ordering
    // guarantee, and a test that depends on one fails on a Tuesday.
    const bookingA = claimed.find((x) => x.riderId === f.riderAId)!;
    const bookingB = claimed.find((x) => x.riderId === f.riderBId)!;
    expect(bookingA.seatCount).toBe(1);
    expect(bookingB.seatCount).toBe(2);
    expect(claimed.every((x) => x.status === BookingStatus.CONFIRMED)).toBe(true);
    expect(
      await prisma.notification.count({
        where: {
          userId: { in: [f.riderAId, f.riderBId] },
          type: NotificationType.POOL_CLAIMED,
        },
      }),
    ).toBe(2);

    // ── 4. It is an ORDINARY trip from here on ───────────────────────────
    //
    // `listMine` is the driver's رحلاتي and knows nothing about pools; a claimed
    // pool has to appear there beside their own posted trips or the whole "no
    // parallel system" claim is false.
    const mine = await trips.listMine(f.driverUserId);
    expect(mine.map((t) => t.id)).toContain(trip.id);

    // …and a THIRD rider, who never heard of the pool, books the last seat
    // through the ordinary Phase 1 path.
    const walkIn = await bookings.book(f.riderCId, {
      tripId: trip.id,
      pickup: { lat: 32.01, lng: 44.31, label: 'صعود ثالث' },
      dropoff: { lat: 32.61, lng: 44.02, label: 'نزول ثالث' },
      seatCount: 1,
    });
    const afterWalkIn = await prisma.trip.findUniqueOrThrow({
      where: { id: trip.id },
    });
    expect(afterWalkIn.seatsAvailable).toBe(0);
    // Full car → LOCKED, exactly as a driver-posted trip would be.
    expect(afterWalkIn.status).toBe(TripStatus.LOCKED);

    // ── 5. The trip runs ─────────────────────────────────────────────────
    await trips.start(f.driverUserId, trip.id);
    expect(
      (await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } })).status,
    ).toBe(TripStatus.EN_ROUTE);

    await bookings.onboard(f.driverUserId, bookingA.id);
    await bookings.onboard(f.driverUserId, walkIn.id);
    // One pooled rider does not turn up — the no-show path must work on a
    // SYSTEM trip exactly as it does on a posted one.
    await bookings.noShow(f.driverUserId, bookingB.id);
    expect(
      await prisma.noShowRecord.count({ where: { riderId: bookingB.riderId } }),
    ).toBe(1);

    // ── 6. It completes, and the money is right ──────────────────────────
    await trips.complete(f.driverUserId, trip.id);
    const settled = await prisma.trip.findUniqueOrThrow({
      where: { id: trip.id },
    });
    expect(settled.status).toBe(TripStatus.SETTLED);

    // The arithmetic, from first principles rather than from a stored counter:
    // rider A's one seat and the walk-in's one seat rode; rider B's two did
    // not.
    const expectedCash = SUGGESTED * 1 + SUGGESTED * 1;
    const money = await earnings.getEarnings(f.driverUserId, 'all');
    expect(money.total).toBe(expectedCash);
    expect(money.records).toHaveLength(1);
    expect(money.records[0].tripId).toBe(trip.id);

    // The no-show's fare is NOT in it — that is the whole point of excluding
    // them, and a sum that happened to match by luck would hide it.
    expect(money.total).not.toBe(SUGGESTED * 4);

    const paid = await prisma.seatBooking.findMany({
      where: { tripId: trip.id },
    });
    expect(
      paid.filter((x) => x.status === BookingStatus.COMPLETED),
    ).toHaveLength(2);
    expect(paid.filter((x) => x.status === BookingStatus.NO_SHOW)).toHaveLength(
      1,
    );
    expect(
      (
        await prisma.driverProfile.findUniqueOrThrow({
          where: { id: f.driverProfileId },
        })
      ).tripsDone,
    ).toBe(1);

    // ── 7. Both directions of rating work on a pooled trip ───────────────
    await ratings.create(f.riderAId, {
      tripId: trip.id,
      toUserId: f.driverUserId,
      score: 5,
    });
    await ratings.create(f.driverUserId, {
      tripId: trip.id,
      toUserId: f.riderAId,
      score: 4,
    });
    // The average lives on DriverProfile — this is the trust signal riders
    // pick a trip on, and a pooled trip must feed it like any other.
    const rated = await prisma.driverProfile.findUniqueOrThrow({
      where: { id: f.driverProfileId },
    });
    expect(rated.ratingAvg).toBeCloseTo(5, 5);

    // ── 8. The seat requests ended honestly ──────────────────────────────
    const finalRequests = await prisma.seatRequest.findMany({
      where: { poolId },
    });
    expect(
      finalRequests.every((r) => r.status === SeatRequestStatus.MATCHED),
    ).toBe(true);
    expect(finalRequests.every((r) => r.bookingId !== null)).toBe(true);
    // And the rider sees a booking, not a request, as the end of the story.
    const riderView = await seatRequests.listMine(f.riderAId);
    expect(riderView[0].stage).toBe('CLAIMED');
    expect(riderView[0].bookingId).toBe(bookingA.id);
  });

  it('a claimed pool can be CANCELLED by the driver like any other trip', async () => {
    // The other end of the lifecycle. Cancelling returns seats and notifies —
    // and none of that code has ever seen a pool.
    const base = Date.now();
    const a = await request(f, f.riderAId, 3, 6, 2, base);
    await request(f, f.riderBId, 3, 6, 1, base);
    const poolId = (
      await prisma.seatRequest.findUniqueOrThrow({ where: { id: a.id } })
    ).poolId!;

    const { trip } = await pools.claim(f.driverUserId, poolId);
    await trips.cancelTrip(f.driverUserId, trip.id);

    const cancelled = await prisma.trip.findUniqueOrThrow({
      where: { id: trip.id },
    });
    expect(cancelled.status).toBe(TripStatus.CANCELLED);
    expect(
      await prisma.notification.count({
        where: {
          userId: { in: [f.riderAId, f.riderBId] },
          type: NotificationType.TRIP_CANCELLED,
        },
      }),
    ).toBe(2);
  });

  it('the raise runs end to end: propose → one accepts, one is silent → trip continues at the new price', async () => {
    const base = Date.now();
    // 2 + 1 seats so the accepter alone still clears POOL_MIN_SEATS — the case
    // where the trip survives with fewer riders is the interesting one.
    const a = await request(f, f.riderAId, 3, 6, 2, base);
    const b = await request(f, f.riderBId, 3, 6, 1, base);
    const poolId = (
      await prisma.seatRequest.findUniqueOrThrow({ where: { id: a.id } })
    ).poolId!;

    const { trip } = await pools.claim(f.driverUserId, poolId);

    // What the DRIVER sees before proposing — computed server-side, and it must
    // agree with what the endpoint will actually accept.
    const before = await pools.driverPoolForTrip(f.driverUserId, trip.id);
    expect(before).not.toBeNull();
    expect(before!.canPropose).toBe(true);
    expect(before!.blockedReason).toBeNull();
    expect(before!.maxPricePerSeat).toBe(MAX_PRICE);
    expect(before!.seatsTaken).toBe(3);
    expect(before!.raise).toBeNull();

    await pools.proposeRaise(f.driverUserId, poolId, 12_000);

    // Now it is a waiting state, and the driver can see who is where.
    const waiting = await pools.driverPoolForTrip(f.driverUserId, trip.id);
    expect(waiting!.canPropose).toBe(false);
    expect(waiting!.blockedReason).toContain('مسبقاً');
    expect(waiting!.raise!.newPricePerSeat).toBe(12_000);
    expect(waiting!.raise!.pendingSeats).toBe(3);
    expect(waiting!.raise!.responses).toHaveLength(2);
    expect(waiting!.raise!.responses.every((r) => r.response === null)).toBe(
      true,
    );

    // Rider A accepts; rider B says nothing and the deadline passes.
    await pools.respondToRaise(f.riderAId, a.id, true);
    const mid = await pools.driverPoolForTrip(f.driverUserId, trip.id);
    expect(mid!.raise!.acceptedSeats).toBe(2);
    expect(mid!.raise!.pendingSeats).toBe(1);

    await pools.resolveRaise(poolId, new Date(Date.now() + HOUR));

    const after = await prisma.trip.findUniqueOrThrow({
      where: { id: trip.id },
    });
    expect(after.status).toBe(TripStatus.OPEN);
    expect(after.pricePerSeat).toBe(12_000);

    // The accepter travels at the new price; the silent rider is released with
    // no penalty and NO no-show record — they refused a new contract, they did
    // not miss a booking.
    const finalBookings = await prisma.seatBooking.findMany({
      where: { tripId: trip.id },
    });
    const alive = finalBookings.filter(
      (x) => x.status === BookingStatus.CONFIRMED,
    );
    expect(alive).toHaveLength(1);
    expect(alive[0].riderId).toBe(f.riderAId);
    expect(alive[0].fare).toBe(12_000 * 2);
    expect(
      await prisma.noShowRecord.count({ where: { riderId: f.riderBId } }),
    ).toBe(0);
    expect(
      (await prisma.seatRequest.findUniqueOrThrow({ where: { id: b.id } }))
        .status,
    ).toBe(SeatRequestStatus.EXPIRED);

    // …and the driver's panel now says what they hold.
    const resolved = await pools.driverPoolForTrip(f.driverUserId, trip.id);
    expect(resolved!.raise!.resolved).toBe(true);
    expect(resolved!.raise!.outcome).toBe('ACCEPTED');
    expect(resolved!.raise!.acceptedSeats).toBe(2);
    // The released rider is still ON the list, flagged — "where did the third
    // one go?" is a question the driver asks, and deleting the row makes the
    // answer a disappearance.
    expect(resolved!.raise!.responses).toHaveLength(2);
    expect(resolved!.raise!.responses.filter((r) => r.released)).toHaveLength(1);

    // The trip still completes and pays out, at the raised price.
    await trips.start(f.driverUserId, trip.id);
    await trips.complete(f.driverUserId, trip.id);
    const money = await earnings.getEarnings(f.driverUserId, 'all');
    expect(money.total).toBe(12_000 * 2);
  });

  it('driverPoolForTrip answers null for a trip the driver POSTED — not an error', async () => {
    // The app asks about every trip without knowing which came from a pool, so
    // "no pool" has to be an answer rather than something to catch.
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      seatsTotal: 4,
      pricePerSeat: SUGGESTED,
      departureTime: new Date(Date.now() + 3 * HOUR).toISOString(),
    });
    await expect(
      pools.driverPoolForTrip(f.driverUserId, posted.id),
    ).resolves.toBeNull();
  });
});
