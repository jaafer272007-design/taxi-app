import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { BookingStatus, DriverStatus, Gender, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { NotificationService } from '../notification/notification.service';
import { StorageService } from '../storage/storage.service';
import { BookingService } from '../booking/booking.service';
import { TripService } from './trip.service';
import { TripContactService } from './trip-contact.service';

/**
 * Who may see whose phone number — against a REAL database.
 *
 * ## Why this boundary is not unit-tested
 *
 * The whole rule lives in a Prisma `where`: `{ tripId, riderId, status: { not:
 * CANCELLED } }`. **A mocked `findFirst` never applies a where clause** — it
 * returns whatever the test handed it. So a unit test of "a rider with a
 * cancelled booking is refused" would be asserting that the mock returned null
 * because the test told it to, which is a test of the test. The same shape of
 * false confidence let departNow trips ship invisible (see
 * booking/trip-search.int-spec.ts).
 *
 * For an access-control rule that is not a tolerable trade. These run the real
 * query against Postgres, so a filter that stops filtering fails here.
 *
 * Requires DATABASE_URL. Run with `npm run test:int` (CI does, after migrate).
 */

const MINUTE = 60_000;

let prisma: PrismaService;
let trips: TripService;
let bookings: BookingService;
let contacts: TripContactService;

const DRIVER_PHONE_SUFFIX = '0000';
const RIDER_PHONE_SUFFIX = '1111';
const CANCELLER_PHONE_SUFFIX = '2222';
const STRANGER_PHONE_SUFFIX = '3333';

interface Fixture {
  tag: string;
  corridorId: string;
  driverProfileId: string;
  driverUserId: string;
  driverPhone: string;
  riderId: string;
  riderPhone: string;
  /** A rider who books and then cancels — entitled to nothing afterwards. */
  cancellerId: string;
  /** A logged-in user with no booking on this trip at all. */
  strangerId: string;
}

/**
 * Phones must be valid, unique and recognisable in assertions. `+9647` + 5 tag
 * digits + a 4-digit role suffix = the 13-char E.164 the schema expects.
 */
function phoneFor(tag: string, suffix: string): string {
  return `+9647${tag}${suffix}`;
}

async function seedFixture(): Promise<Fixture> {
  // Digits only: the tag is spliced into a phone number.
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const corridor = await prisma.corridor.create({
    data: {
      // Scratch cities, never one of the 18 real ones — the seeded 306-pair
      // grid holds a unique index on (originCity, destCity).
      originCity: `CT-${tag}-A`,
      destCity: `CT-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: phoneFor(tag, DRIVER_PHONE_SUFFIX),
      name: 'سائق التواصل',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: { make: 'Toyota', model: 'Corolla', plate: `CT-${tag}`, color: 'أبيض', seats: 4 },
          },
        },
      },
    },
    include: { driver: true },
  });

  const [rider, canceller, stranger] = await Promise.all([
    prisma.user.create({
      data: {
        phone: phoneFor(tag, RIDER_PHONE_SUFFIX),
        name: 'راكبة مؤكدة',
        gender: Gender.FEMALE,
        roles: [UserRole.RIDER],
      },
    }),
    prisma.user.create({
      data: {
        phone: phoneFor(tag, CANCELLER_PHONE_SUFFIX),
        name: 'راكبة ألغت',
        gender: Gender.FEMALE,
        roles: [UserRole.RIDER],
      },
    }),
    prisma.user.create({
      data: {
        phone: phoneFor(tag, STRANGER_PHONE_SUFFIX),
        name: 'مستخدم غريب',
        gender: Gender.FEMALE,
        roles: [UserRole.RIDER],
      },
    }),
  ]);

  return {
    tag,
    corridorId: corridor.id,
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    driverPhone: driverUser.phone,
    riderId: rider.id,
    riderPhone: rider.phone,
    cancellerId: canceller.id,
    strangerId: stranger.id,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  await prisma.seatBooking.deleteMany({ where: { trip: { corridorId: f.corridorId } } });
  await prisma.trip.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.vehicle.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.document.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.driverProfile.deleteMany({ where: { id: f.driverProfileId } });
  await prisma.user.deleteMany({
    where: { id: { in: [f.driverUserId, f.riderId, f.cancellerId, f.strangerId] } },
  });
  await prisma.corridor.deleteMany({ where: { id: f.corridorId } });
}

/** A scheduled trip 3 hours out — comfortably inside the free-cancel window. */
function postTrip(f: Fixture) {
  return trips.createTrip(f.driverUserId, {
    corridorId: f.corridorId,
    departureTime: new Date(Date.now() + 180 * MINUTE).toISOString(),
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

beforeAll(async () => {
  prisma = new PrismaService();
  await prisma.$connect();

  const notifications = { send: async () => {} } as unknown as NotificationService;
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  trips = new TripService(prisma, drivers, corridors, notifications);
  bookings = new BookingService(prisma, drivers, notifications);
  contacts = new TripContactService(prisma, drivers);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('trip contacts — who may see a phone number (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('a rider with a confirmed booking sees the DRIVER, and only the driver', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);

    const result = await contacts.listContacts(f.riderId, trip.id);

    expect(result.role).toBe('RIDER');
    expect(result.contacts).toHaveLength(1);
    expect(result.contacts[0]).toMatchObject({
      userId: f.driverUserId,
      phone: f.driverPhone,
      bookingId: booking.id,
    });
  });

  it("the trip's driver sees each booked rider's number", async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);

    const result = await contacts.listContacts(f.driverUserId, trip.id);

    expect(result.role).toBe('DRIVER');
    expect(result.contacts).toHaveLength(1);
    expect(result.contacts[0]).toMatchObject({
      userId: f.riderId,
      phone: f.riderPhone,
      bookingId: booking.id,
    });
  });

  it('a rider whose booking is CANCELLED is refused — 403, not an empty list', async () => {
    // The distinction matters: an empty list reads as "nobody to call" and the
    // UI would render a blank contact row. A 403 says "not yours".
    const trip = await postTrip(f);
    const booking = await book(f.cancellerId, trip.id);
    await bookings.cancel(f.cancellerId, booking.id);

    const after = await prisma.seatBooking.findUniqueOrThrow({ where: { id: booking.id } });
    expect(after.status).toBe(BookingStatus.CANCELLED); // precondition, not the assertion

    await expect(contacts.listContacts(f.cancellerId, trip.id)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('the driver no longer sees a rider who cancelled', async () => {
    // The rule cuts BOTH ways. A driver keeping the number of someone who
    // pulled out is the same leak seen from the other side.
    const trip = await postTrip(f);
    const staying = await book(f.riderId, trip.id);
    const leaving = await book(f.cancellerId, trip.id);
    await bookings.cancel(f.cancellerId, leaving.id);

    const result = await contacts.listContacts(f.driverUserId, trip.id);

    expect(result.contacts.map((c) => c.userId)).toEqual([f.riderId]);
    expect(result.contacts.map((c) => c.bookingId)).toEqual([staying.id]);
  });

  it('an unrelated signed-in user is refused', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    await expect(contacts.listContacts(f.strangerId, trip.id)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('a rider with a booking on ANOTHER trip is refused on this one', async () => {
    // Having *a* booking is not having a booking *here* — the tripId has to be
    // part of the predicate, and a mocked query would happily pretend it is.
    const mine = await postTrip(f);
    const theirs = await postTrip(f);
    await book(f.strangerId, theirs.id);

    await expect(contacts.listContacts(f.strangerId, mine.id)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('a NO_SHOW booking still grants contact — the ride happened', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id);
    await bookings.noShow(f.driverUserId, booking.id);

    const result = await contacts.listContacts(f.riderId, trip.id);

    expect(result.contacts[0].phone).toBe(f.driverPhone);
  });

  it('a driver with no bookings yet gets an empty list, not a 403', async () => {
    // They own the trip; there is simply nobody on it. That is a different
    // answer from "you may not ask".
    const trip = await postTrip(f);

    const result = await contacts.listContacts(f.driverUserId, trip.id);

    expect(result).toEqual({ role: 'DRIVER', contacts: [] });
  });

  it('an unknown trip is 404 for everyone, including the driver', async () => {
    await expect(contacts.listContacts(f.driverUserId, 'no-such-trip')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

describe('no phone number leaks from any other endpoint (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('trip search returns no phone number — this is the pre-booking screen', async () => {
    // The harvesting case: anyone may search, so a number here would hand every
    // driver's mobile to anyone willing to scroll.
    const trip = await postTrip(f);

    const results = await bookings.search({ corridorId: f.corridorId });
    expect(results.map((t) => t.id)).toContain(trip.id);

    // Not a field-name check: serialise the whole payload and look for the
    // digits themselves, so a phone smuggled under any key name is caught.
    const payload = JSON.stringify(results);
    expect(payload).not.toContain(f.driverPhone);
    expect(payload).not.toContain('+9647');
  });

  it("the driver's booking list carries coordinates but still no rider phone", async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const rows = await trips.listBookings(f.driverUserId, trip.id);

    expect(rows[0]).toMatchObject({ pickupLat: 32.0, pickupLng: 44.3 });
    expect(JSON.stringify(rows)).not.toContain('+9647');
  });

  it("the rider's own booking list carries coordinates but no driver phone", async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const rows = await bookings.listMine(f.riderId);

    expect(rows[0]).toMatchObject({ pickupLat: 32.0, dropoffLng: 44.0 });
    expect(JSON.stringify(rows)).not.toContain('+9647');
  });
});
