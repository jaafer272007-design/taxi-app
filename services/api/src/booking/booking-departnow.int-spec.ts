import { BookingStatus, DriverStatus, Gender, TripStatus, UserRole } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { StorageService } from '../storage/storage.service';
import { NotificationService } from '../notification/notification.service';
import { TripService } from '../trip/trip.service';
import { BookingService } from './booking.service';
import { NoShowService } from './no-show.service';

/**
 * THE MONEY BUG, against a REAL database.
 *
 * Found in live testing: a rider booked seats and could neither find nor cancel
 * them. One root cause with four faces, and every one of them was a raw
 * `departureTime > now` written out by hand instead of asking `trip-window.ts`:
 *
 *  1. `isBookingUpcoming` — a **departNow trip has `departureTime === now`**, so
 *     a booking on a trip that search was still offering landed in «سابقة»
 *     before the tap finished.
 *  2. From there the app's `canCancel` (which requires `upcoming`) drew no
 *     cancel button, and `hasLiveBookings` was false so حجوزاتي stopped polling
 *     — which is why a second booking never appeared in EITHER tab.
 *  3. `BookingService.cancel`'s cutoff was `departureTime - 15min`, already
 *     expired when the row was created, so even calling the API directly got
 *     «فات وقت الإلغاء المجاني». The seats were held with no way out.
 *  4. `cancel`'s reopen check left a full departNow trip LOCKED for the rest of
 *     its window, so a freed seat was never re-offered.
 *
 * **Why these tests are integration tests.** Every unit test of
 * `isBookingUpcoming` passed throughout, because they all fed it a fixture with
 * `departNow: false` — the field did not even exist on the input type. The bug
 * lives in the interaction between how a trip is POSTED and how a booking is
 * later READ, so only a real post → book → read → cancel round trip sees it.
 *
 * Requires DATABASE_URL. Run with `npm run test:int` (CI does, after migrate).
 */

const MINUTE = 60_000;

let prisma: PrismaService;
let trips: TripService;
let bookings: BookingService;

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
      originCity: `DN-${tag}-A`,
      destCity: `DN-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+9648${tag}0000`,
      name: 'سائق الآن',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: `DN-${tag}`,
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
        phone: `+9648${tag}1111`,
        name: 'راكب الآن',
        gender: Gender.MALE,
        roles: [UserRole.RIDER],
      },
    }),
    prisma.user.create({
      data: {
        phone: `+9648${tag}2222`,
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

/** «الآن» — departureTime IS now. The shape the whole bug turned on. */
function postDepartNowTrip(f: Fixture, seatsTotal = 4) {
  return trips.createTrip(f.driverUserId, {
    corridorId: f.corridorId,
    departNow: true,
    seatsTotal,
    pricePerSeat: 12000,
  });
}

function postScheduledTrip(f: Fixture, seatsTotal = 4) {
  return trips.createTrip(f.driverUserId, {
    corridorId: f.corridorId,
    departureTime: new Date(Date.now() + 300 * MINUTE).toISOString(),
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

/** The booking as the rider's حجوزاتي receives it. */
async function mine(riderId: string, bookingId: string) {
  const list = await bookings.listMine(riderId);
  const found = list.find((b) => b.id === bookingId);
  if (!found) throw new Error(`booking ${bookingId} missing from listMine`);
  return found;
}

const seatsOf = (tripId: string) =>
  prisma.trip.findUniqueOrThrow({ where: { id: tripId } });

beforeAll(async () => {
  prisma = new PrismaService();
  await prisma.$connect();

  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  const noShows = new NoShowService(prisma, config);
  trips = new TripService(prisma, drivers, corridors, notifications, noShows);
  bookings = new BookingService(prisma, drivers, notifications, noShows);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('a booking on a LIVE «الآن» trip belongs under «قادمة»', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('is upcoming the moment it is made — the trip is still in search', async () => {
    const trip = await postDepartNowTrip(f);

    // Precondition, asserted rather than assumed: this trip is LIVE. If search
    // is offering it, a booking on it cannot possibly be history.
    const results = await bookings.search({ corridorId: f.corridorId });
    expect(results.map((t) => t.id)).toContain(trip.id);

    const booking = await book(f.riderId, trip.id, 2);
    const seen = await mine(f.riderId, booking.id);

    expect(seen.status).toBe(BookingStatus.CONFIRMED);
    expect(seen.trip.status).toBe(TripStatus.OPEN);
    expect(seen.trip.departNow).toBe(true);
    // departureTime is in the PAST by definition — that is the whole trap.
    expect(seen.trip.departureTime.getTime()).toBeLessThanOrEqual(Date.now());
    expect(seen.upcoming).toBe(true);
  });

  it('and the rider can actually cancel it, getting every seat back', async () => {
    const trip = await postDepartNowTrip(f);
    const booking = await book(f.riderId, trip.id, 2);
    expect((await seatsOf(trip.id)).seatsAvailable).toBe(2);

    // This threw «فات وقت الإلغاء المجاني» before the fix: the cutoff was
    // measured from departureTime, which for «الآن» is already behind us.
    await bookings.cancel(f.riderId, booking.id);

    const after = await seatsOf(trip.id);
    expect(after.seatsAvailable).toBe(4);
    expect((await mine(f.riderId, booking.id)).status).toBe(BookingStatus.CANCELLED);
  });

  it('cancelling the last seat REOPENS a departNow trip that had locked', async () => {
    const trip = await postDepartNowTrip(f, 2);
    const booking = await book(f.riderId, trip.id, 2);
    expect((await seatsOf(trip.id)).status).toBe(TripStatus.LOCKED);

    await bookings.cancel(f.riderId, booking.id);

    const after = await seatsOf(trip.id);
    expect(after.seatsAvailable).toBe(2);
    // Left LOCKED before the fix, so the freed seat was never re-offered and
    // the driver carried an empty place through the whole window.
    expect(after.status).toBe(TripStatus.OPEN);
    const results = await bookings.search({ corridorId: f.corridorId });
    expect(results.map((t) => t.id)).toContain(trip.id);
  });

  it('a scheduled trip is unaffected — the old rule was right about those', async () => {
    const trip = await postScheduledTrip(f);
    const booking = await book(f.riderId, trip.id, 1);
    expect((await mine(f.riderId, booking.id)).upcoming).toBe(true);
    await bookings.cancel(f.riderId, booking.id);
    expect((await mine(f.riderId, booking.id)).status).toBe(BookingStatus.CANCELLED);
  });
});

describe('every booking a rider holds is retrievable and cancellable', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('across several trips of both kinds, listMine returns them all as upcoming', async () => {
    const [now1, now2, sched] = await Promise.all([
      postDepartNowTrip(f),
      postDepartNowTrip(f),
      postScheduledTrip(f),
    ]);
    const made = [
      await book(f.riderId, now1.id, 2),
      await book(f.riderId, now2.id, 1),
      await book(f.riderId, sched.id, 3),
    ];

    const list = await bookings.listMine(f.riderId);

    // Nothing may go missing: the rider reported bookings in NEITHER tab, and
    // upcoming/past partition the list, so "missing" can only mean "not
    // returned" or "never refreshed".
    expect(list).toHaveLength(3);
    expect(list.map((b) => b.id).sort()).toEqual(made.map((b) => b.id).sort());
    expect(list.every((b) => b.upcoming === true)).toBe(true);

    // …and each one can be released.
    for (const b of made) {
      await bookings.cancel(f.riderId, b.id);
    }
    const after = await bookings.listMine(f.riderId);
    expect(after.every((b) => b.status === BookingStatus.CANCELLED)).toBe(true);
    expect(after.every((b) => b.upcoming === false)).toBe(true);
  });
});

describe('one booking per rider per trip, with a way to change it', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('refuses a second booking on the same trip and holds the seats steady', async () => {
    const trip = await postScheduledTrip(f);
    await book(f.riderId, trip.id, 2);

    await expect(book(f.riderId, trip.id, 2)).rejects.toThrow(
      /لديك حجز على هذه الرحلة بالفعل/,
    );

    // The guard runs INSIDE the transaction, after the seat decrement, so the
    // rollback is what keeps this honest. Without it the refusal would still
    // have eaten two seats.
    expect((await seatsOf(trip.id)).seatsAvailable).toBe(2);
  });

  it('closes the hole that let one rider hold 8 seats behind a 4-seat cap', async () => {
    // 4 + 4 through two bookings was the bypass. The cap is per booking, so the
    // only way to make it mean anything is one booking per rider per trip.
    //
    // Needs a vehicle big enough to hold 8, or the trip is refused for
    // capacity and the test would pass without exercising the guard at all.
    await prisma.vehicle.update({
      where: { driverId: f.driverProfileId },
      data: { seats: 8 },
    });
    const trip = await trips.createTrip(f.driverUserId, {
      corridorId: f.corridorId,
      departureTime: new Date(Date.now() + 300 * MINUTE).toISOString(),
      seatsTotal: 8,
      pricePerSeat: 12000,
    });
    await book(f.riderId, trip.id, 4);
    await expect(book(f.riderId, trip.id, 4)).rejects.toThrow(/بالفعل/);
    expect((await seatsOf(trip.id)).seatsAvailable).toBe(4);
  });

  it('a different rider is of course still free to book', async () => {
    const trip = await postScheduledTrip(f);
    await book(f.riderId, trip.id, 1);
    await expect(book(f.otherRiderId, trip.id, 1)).resolves.toBeDefined();
    expect((await seatsOf(trip.id)).seatsAvailable).toBe(2);
  });

  it('re-booking is allowed again once the earlier booking is cancelled', async () => {
    const trip = await postScheduledTrip(f);
    const first = await book(f.riderId, trip.id, 1);
    await bookings.cancel(f.riderId, first.id);
    await expect(book(f.riderId, trip.id, 2)).resolves.toBeDefined();
  });

  it('changeSeats grows and shrinks, moving the fare and the trip status with it', async () => {
    const trip = await postScheduledTrip(f);
    const booking = await book(f.riderId, trip.id, 2);

    const grown = await bookings.changeSeats(f.riderId, booking.id, 4);
    expect(grown.seatCount).toBe(4);
    expect(grown.fare).toBe(4 * 12000);
    const full = await seatsOf(trip.id);
    expect(full.seatsAvailable).toBe(0);
    expect(full.status).toBe(TripStatus.LOCKED); // filled up

    const shrunk = await bookings.changeSeats(f.riderId, booking.id, 1);
    expect(shrunk.seatCount).toBe(1);
    expect(shrunk.fare).toBe(12000);
    const reopened = await seatsOf(trip.id);
    expect(reopened.seatsAvailable).toBe(3);
    expect(reopened.status).toBe(TripStatus.OPEN); // and reopened
  });

  it('refuses to grow past what the trip has, leaving the booking untouched', async () => {
    const trip = await postScheduledTrip(f, 2);
    const booking = await book(f.riderId, trip.id, 1);

    await expect(bookings.changeSeats(f.riderId, booking.id, 4)).rejects.toThrow(
      /المقاعد المطلوبة غير متاحة/,
    );

    expect((await mine(f.riderId, booking.id)).seatCount).toBe(1);
    expect((await seatsOf(trip.id)).seatsAvailable).toBe(1);
  });

  it('works on a departNow booking too — the reason the rider needed it', async () => {
    const trip = await postDepartNowTrip(f);
    const booking = await book(f.riderId, trip.id, 1);
    const grown = await bookings.changeSeats(f.riderId, booking.id, 3);
    expect(grown.seatCount).toBe(3);
    expect((await seatsOf(trip.id)).seatsAvailable).toBe(1);
  });

  it('is not something one rider can do to another rider’s booking', async () => {
    const trip = await postScheduledTrip(f);
    const booking = await book(f.riderId, trip.id, 1);
    await expect(
      bookings.changeSeats(f.otherRiderId, booking.id, 2),
    ).rejects.toThrow(/هذا ليس حجزك/);
  });
});
