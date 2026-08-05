import { ConflictException } from '@nestjs/common';
import { DriverStatus, TripStatus, UserRole, Gender } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { NotificationService } from '../notification/notification.service';
import { StorageService } from '../storage/storage.service';
import { TripService } from '../trip/trip.service';
import { BookingService } from './booking.service';
import { expireStaleTrips } from '../trip/trip-expiry';
import { DEPART_NOW_WINDOW_MINUTES } from '../trip/trip-window';

/**
 * post → search, in sequence, against a REAL database.
 *
 * ## Why this file exists
 *
 * Every other spec in this service mocks Prisma. A mocked `findMany` returns
 * whatever the test told it to and never applies the `where` clause, so a unit
 * test on search can assert the *shape* of the filter but never its *effect* —
 * and every unit test here passed while `departNow` trips were invisible to
 * every rider in production.
 *
 * The two halves were also tested apart: one spec proved `POST /trips` stores a
 * departNow trip correctly, another proved search returns "future OPEN trips".
 * Both were true. The bug lived in the seam.
 *
 * So this runs the real create, then the real query, against Postgres. It is the
 * test that would have caught it.
 *
 * Requires DATABASE_URL. Run with `npm run test:int` (CI does, after migrate).
 */

const MINUTE = 60_000;

let prisma: PrismaService;
let trips: TripService;
let bookings: BookingService;

/** Fixtures for one test, namespaced so parallel/repeat runs cannot collide. */
interface Fixture {
  corridorId: string;
  driverProfileId: string;
  driverUserId: string;
  riderId: string;
}

async function seedFixture(tag: string): Promise<Fixture> {
  const corridor = await prisma.corridor.create({
    data: {
      // Deliberately NOT one of the 18 real cities: this row is scratch data and
      // must never collide with the seeded 306-corridor grid's unique pair index.
      originCity: `IT-${tag}-A`,
      destCity: `IT-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+96470${tag}`.slice(0, 14),
      name: 'سائق التكامل',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: { make: 'Toyota', model: 'Corolla', plate: `IT-${tag}`, color: 'أبيض', seats: 4 },
          },
        },
      },
    },
    include: { driver: true },
  });

  const rider = await prisma.user.create({
    data: {
      phone: `+96471${tag}`.slice(0, 14),
      name: 'راكب التكامل',
      gender: Gender.FEMALE,
      roles: [UserRole.RIDER],
    },
  });

  return {
    corridorId: corridor.id,
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    riderId: rider.id,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  await prisma.seatBooking.deleteMany({ where: { trip: { corridorId: f.corridorId } } });
  await prisma.trip.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.vehicle.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.document.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.driverProfile.deleteMany({ where: { id: f.driverProfileId } });
  await prisma.user.deleteMany({ where: { id: { in: [f.driverUserId, f.riderId] } } });
  await prisma.corridor.deleteMany({ where: { id: f.corridorId } });
}

/** Shift a trip's departure into the past to simulate elapsed time. */
function backdate(tripId: string, minutes: number, departNow: boolean): Promise<unknown> {
  return prisma.trip.update({
    where: { id: tripId },
    data: { departureTime: new Date(Date.now() - minutes * MINUTE), departNow },
  });
}

beforeAll(async () => {
  prisma = new PrismaService();
  await prisma.$connect();

  const notifications = { send: async () => {} } as unknown as NotificationService;
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  trips = new TripService(prisma, drivers, corridors, notifications);
  bookings = new BookingService(prisma, drivers, notifications);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('post → search (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture(Math.random().toString(36).slice(2, 8));
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('a departNow trip is findable immediately after it is posted', async () => {
    // The exact reproduction from live testing: driver posts «الآن», rider
    // searches the same corridor seconds later.
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    expect(posted.status).toBe(TripStatus.OPEN);
    expect(posted.departNow).toBe(true);

    const found = await bookings.search({ corridorId: f.corridorId });

    expect(found.map((t) => t.id)).toContain(posted.id);
  });

  it('a departNow trip is still findable late in its window', async () => {
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    await backdate(posted.id, DEPART_NOW_WINDOW_MINUTES - 1, true);

    const found = await bookings.search({ corridorId: f.corridorId });

    expect(found.map((t) => t.id)).toContain(posted.id);
  });

  it('a departNow trip is NOT findable once its window has expired', async () => {
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    await backdate(posted.id, DEPART_NOW_WINDOW_MINUTES + 1, true);

    const found = await bookings.search({ corridorId: f.corridorId });

    expect(found.map((t) => t.id)).not.toContain(posted.id);
  });

  it('a SCHEDULED trip whose departure has passed is still excluded', async () => {
    // The half of the rule that must not be relaxed. Note the trip is backdated
    // by less than the departNow window: a blanket grace period would wrongly
    // resurrect it, and this asserts we did not implement one.
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departureTime: new Date(Date.now() + 2 * 60 * MINUTE).toISOString(),
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    await backdate(posted.id, DEPART_NOW_WINDOW_MINUTES - 5, false);

    const found = await bookings.search({ corridorId: f.corridorId });

    expect(found.map((t) => t.id)).not.toContain(posted.id);
  });

  it('a scheduled trip in the future is findable, as it always was', async () => {
    // Guards against "fixing" search by breaking the ordinary case.
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departureTime: new Date(Date.now() + 3 * 60 * MINUTE).toISOString(),
      seatsTotal: 4,
      pricePerSeat: 12000,
    });

    const found = await bookings.search({ corridorId: f.corridorId });

    expect(found.map((t) => t.id)).toContain(posted.id);
  });
});

describe('post → search → book (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture(Math.random().toString(36).slice(2, 8));
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('a departNow trip a rider can SEE is a trip they can BOOK', async () => {
    // Fixing search alone would have produced a worse bug than the original:
    // the trip appears in the results and «احجز مقعد» answers "this trip has
    // expired". Visible and bookable have to be the same predicate.
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });

    const found = await bookings.search({ corridorId: f.corridorId });
    expect(found.map((t) => t.id)).toContain(posted.id);

    const booking = await bookings.book(f.riderId, {
      tripId: posted.id,
      pickup: { lat: 32.0, lng: 44.3, label: 'نقطة الانطلاق' },
      dropoff: { lat: 32.6, lng: 44.0, label: 'نقطة الوصول' },
      seatCount: 1,
    });

    expect(booking.tripId).toBe(posted.id);
    expect(booking.fare).toBe(12000);
  });

  it('an expired departNow trip refuses the booking', async () => {
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    await backdate(posted.id, DEPART_NOW_WINDOW_MINUTES + 1, true);

    await expect(
      bookings.book(f.riderId, {
        tripId: posted.id,
        pickup: { lat: 32.0, lng: 44.3, label: 'A' },
        dropoff: { lat: 32.6, lng: 44.0, label: 'B' },
        seatCount: 1,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});

describe('expiry sweep (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture(Math.random().toString(36).slice(2, 8));
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('CANCELS an expired departNow trip nobody booked, so it stops lingering as OPEN', async () => {
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    await backdate(posted.id, DEPART_NOW_WINDOW_MINUTES + 1, true);

    await expireStaleTrips(prisma);

    const after = await prisma.trip.findUniqueOrThrow({ where: { id: posted.id } });
    expect(after.status).toBe(TripStatus.CANCELLED);
  });

  it('LOCKS an expired departNow trip that carried a rider', async () => {
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });
    await bookings.book(f.riderId, {
      tripId: posted.id,
      pickup: { lat: 32.0, lng: 44.3, label: 'A' },
      dropoff: { lat: 32.6, lng: 44.0, label: 'B' },
      seatCount: 1,
    });
    await backdate(posted.id, DEPART_NOW_WINDOW_MINUTES + 1, true);

    await expireStaleTrips(prisma);

    const after = await prisma.trip.findUniqueOrThrow({ where: { id: posted.id } });
    expect(after.status).toBe(TripStatus.LOCKED);
  });

  it('leaves a still-live departNow trip alone', async () => {
    const posted = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departNow: true,
      seatsTotal: 4,
      pricePerSeat: 12000,
    });

    await expireStaleTrips(prisma);

    const after = await prisma.trip.findUniqueOrThrow({ where: { id: posted.id } });
    expect(after.status).toBe(TripStatus.OPEN);
  });
});
