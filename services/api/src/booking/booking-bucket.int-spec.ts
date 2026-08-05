import { BookingStatus, DriverStatus, Gender, TripStatus, UserRole } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { StorageService } from '../storage/storage.service';
import { NotificationService } from '../notification/notification.service';
import { TripService } from '../trip/trip.service';
import { RatingService } from '../rating/rating.service';
import { BookingService } from './booking.service';

/**
 * Two bugs from live end-to-end testing, both on the rider side after a trip
 * completed — against a REAL database, because both are interactions rather
 * than functions.
 *
 * **1. A COMPLETED booking sat under «قادمة».** The bucket asked
 * `departureTime > now`, so a trip completed early — scheduled for tonight,
 * driven this afternoon — filed the finished booking as upcoming. A unit test
 * of the predicate cannot catch this: the predicate was never wrong about the
 * clock, it was being asked the wrong question, and the wrong question was
 * only visible once a real trip had really been completed.
 *
 * **2. The rider could not rate the driver.** Everything the server needed
 * existed; what was missing was the driver's USER id in the payload and any
 * notion of "already rated". Driver `ratingAvg` is what riders choose a trip
 * on, so it has to actually move — asserted here on the row, not on a return
 * value.
 *
 * Requires DATABASE_URL. Run with `npm run test:int` (CI does, after migrate).
 */

const MINUTE = 60_000;

let prisma: PrismaService;
let trips: TripService;
let bookings: BookingService;
let ratings: RatingService;

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
      originCity: `BB-${tag}-A`,
      destCity: `BB-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+9647${tag}0000`,
      name: 'سائق التقييم',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: `BB-${tag}`,
              color: 'أبيض',
              seats: 4,
            },
          },
        },
      },
    },
    include: { driver: true },
  });

  const [rider, otherRider] = await Promise.all([
    prisma.user.create({
      data: {
        phone: `+9647${tag}1111`,
        name: 'راكب المقيّم',
        gender: Gender.MALE,
        roles: [UserRole.RIDER],
      },
    }),
    prisma.user.create({
      data: {
        phone: `+9647${tag}2222`,
        name: 'راكب آخر',
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

/** A trip departing well into the future — the condition the old rule got wrong. */
function postFutureTrip(f: Fixture) {
  return trips.createTrip(f.driverUserId, {
    corridorId: f.corridorId,
    departureTime: new Date(Date.now() + 300 * MINUTE).toISOString(),
    seatsTotal: 4,
    pricePerSeat: 12000,
  });
}

function book(riderId: string, tripId: string) {
  return bookings.book(riderId, {
    tripId,
    pickup: { lat: 32.0, lng: 44.3, label: 'نقطة الانطلاق' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'نقطة الوصول' },
    seatCount: 1,
  });
}

/** The booking as the rider's حجوزاتي receives it. */
async function mine(riderId: string, bookingId: string) {
  const list = await bookings.listMine(riderId);
  const found = list.find((b) => b.id === bookingId);
  if (!found) throw new Error(`booking ${bookingId} missing from listMine`);
  return found;
}

beforeAll(async () => {
  prisma = new PrismaService();
  await prisma.$connect();

  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  trips = new TripService(prisma, drivers, corridors, notifications);
  bookings = new BookingService(prisma, drivers, notifications);
  ratings = new RatingService(prisma);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('BUG 1 — «قادمة» / «سابقة» is decided by status, not the clock', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('a COMPLETED booking on a trip that had not yet been due is PAST', async () => {
    // The exact reproduction: post for five hours from now, drive it anyway,
    // complete it. The badge said «مكتملة» while the filter said «قادمة».
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);

    const before = await mine(f.riderId, booking.id);
    expect(before.upcoming).toBe(true); // still actionable — correctly upcoming

    await trips.start(f.driverUserId, trip.id);
    await trips.complete(f.driverUserId, trip.id);

    const after = await mine(f.riderId, booking.id);
    expect(after.status).toBe(BookingStatus.COMPLETED);
    // Departure is STILL in the future. Under the old rule this was `true`.
    expect(after.trip.departureTime.getTime()).toBeGreaterThan(Date.now());
    expect(after.upcoming).toBe(false);
  });

  it('a trip the driver cancelled is PAST even though it was due tomorrow', async () => {
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);

    await trips.cancelTrip(f.driverUserId, trip.id);

    const after = await mine(f.riderId, booking.id);
    expect(after.trip.status).toBe(TripStatus.CANCELLED);
    expect(after.upcoming).toBe(false);
  });

  it('a booking the RIDER cancelled is PAST', async () => {
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);

    await bookings.cancel(f.riderId, booking.id);

    const after = await mine(f.riderId, booking.id);
    expect(after.status).toBe(BookingStatus.CANCELLED);
    expect(after.upcoming).toBe(false);
  });

  it('a journey in progress is UPCOMING, not past', async () => {
    // EN_ROUTE means departure has passed by definition; filing a trip the
    // rider is sitting in under «سابقة» is the same mistake mirrored.
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id);

    const after = await mine(f.riderId, booking.id);
    expect(after.trip.status).toBe(TripStatus.EN_ROUTE);
    expect(after.upcoming).toBe(true);
  });

  it('an untouched future booking stays UPCOMING — the fix is narrow', async () => {
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);

    const row = await mine(f.riderId, booking.id);
    expect(row.upcoming).toBe(true);
  });
});

describe('BUG 2 — the rider can rate their driver after completion', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  /** Run a trip end to end and hand back the rider's completed booking id. */
  async function completedTrip(): Promise<{ tripId: string; bookingId: string }> {
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id);
    await trips.complete(f.driverUserId, trip.id);
    return { tripId: trip.id, bookingId: booking.id };
  }

  it('the payload carries who to rate, and that it has not been rated yet', async () => {
    const { bookingId } = await completedTrip();

    const row = await mine(f.riderId, bookingId);
    // Without these two fields the rider app has no one to address a rating to
    // and no way to stop offering it twice — the whole of bug 2.
    expect(row.driverUserId).toBe(f.driverUserId);
    expect(row.ratable).toBe(true);
    expect(row.ratedDriver).toBe(false);
  });

  it("rating actually moves the driver's ratingAvg — the trust signal", async () => {
    const { tripId } = await completedTrip();

    const before = await prisma.driverProfile.findUnique({
      where: { id: f.driverProfileId },
      select: { ratingAvg: true },
    });
    expect(before!.ratingAvg).toBe(0);

    await ratings.create(f.riderId, {
      tripId,
      toUserId: f.driverUserId,
      score: 4,
      comment: 'سائق محترم',
    });

    // Asserted on the ROW, not on what create() returned: search reads
    // DriverProfile.ratingAvg, and that is the number a rider chooses on.
    const after = await prisma.driverProfile.findUnique({
      where: { id: f.driverProfileId },
      select: { ratingAvg: true },
    });
    expect(after!.ratingAvg).toBe(4);
  });

  it('the booking reports itself rated afterwards, so the action stops showing', async () => {
    const { tripId, bookingId } = await completedTrip();
    await ratings.create(f.riderId, { tripId, toUserId: f.driverUserId, score: 5 });

    const row = await mine(f.riderId, bookingId);
    expect(row.ratedDriver).toBe(true);
  });

  it('a second rating for the same trip is refused', async () => {
    const { tripId } = await completedTrip();
    await ratings.create(f.riderId, { tripId, toUserId: f.driverUserId, score: 5 });

    await expect(
      ratings.create(f.riderId, { tripId, toUserId: f.driverUserId, score: 1 }),
    ).rejects.toMatchObject({ status: 409 });

    // …and the average is untouched by the refused attempt.
    const profile = await prisma.driverProfile.findUnique({
      where: { id: f.driverProfileId },
      select: { ratingAvg: true },
    });
    expect(profile!.ratingAvg).toBe(5);
  });

  it('cannot rate before the trip is completed', async () => {
    const trip = await postFutureTrip(f);
    await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id); // EN_ROUTE, not finished

    await expect(
      ratings.create(f.riderId, { tripId: trip.id, toUserId: f.driverUserId, score: 5 }),
    ).rejects.toMatchObject({ status: 409 });
  });

  it('a rider who was not on the trip cannot rate its driver', async () => {
    const { tripId } = await completedTrip();

    await expect(
      ratings.create(f.otherRiderId, { tripId, toUserId: f.driverUserId, score: 1 }),
    ).rejects.toMatchObject({ status: 403 });
  });

  it("one rider's rating does not mark another rider's booking rated", async () => {
    // `ratedDriver` is derived from a set keyed by (tripId, toUserId) for THIS
    // rider. Keyed only by tripId it would hide the action from everyone the
    // moment one passenger rated.
    const trip = await postFutureTrip(f);
    const mineBooking = await book(f.riderId, trip.id);
    await book(f.otherRiderId, trip.id);
    await trips.start(f.driverUserId, trip.id);
    await trips.complete(f.driverUserId, trip.id);

    await ratings.create(f.otherRiderId, {
      tripId: trip.id,
      toUserId: f.driverUserId,
      score: 3,
    });

    const row = await mine(f.riderId, mineBooking.id);
    expect(row.ratedDriver).toBe(false);
  });

  it('a booking that never rode is not ratable', async () => {
    const trip = await postFutureTrip(f);
    const booking = await book(f.riderId, trip.id);
    await bookings.cancel(f.riderId, booking.id);

    const row = await mine(f.riderId, booking.id);
    expect(row.ratable).toBe(false);
  });
});
