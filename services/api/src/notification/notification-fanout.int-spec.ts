import { DriverStatus, Gender, NotificationType, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { StorageService } from '../storage/storage.service';
import { ConfigService } from '@nestjs/config';
import { TripService } from '../trip/trip.service';
import { BookingService } from '../booking/booking.service';
import { NotificationService } from './notification.service';

/**
 * Who actually receives which event — against a REAL database.
 *
 * Fan-out is not a property of any one function: it is the result of a service
 * choosing a recipient, resolving them (driverProfileId → userId, tripId →
 * every rider holding a booking), and the emitter writing a row. With Prisma
 * mocked, every one of those lookups returns whatever the test handed it, so
 * "the rider was notified and the driver was not" would be a statement about
 * the mock.
 *
 * The case that matters most is the one from live testing: **a driver cancels
 * a booked trip.** The riders found out by arriving at a pickup point for a
 * trip that no longer existed.
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
  riderAId: string;
  riderBId: string;
}

async function seedFixture(): Promise<Fixture> {
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const corridor = await prisma.corridor.create({
    data: {
      originCity: `NT-${tag}-A`,
      destCity: `NT-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+9647${tag}0000`,
      name: 'سائق الإشعارات',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: { make: 'Toyota', model: 'Corolla', plate: `NT-${tag}`, color: 'أبيض', seats: 4 },
          },
        },
      },
    },
    include: { driver: true },
  });

  const [riderA, riderB] = await Promise.all([
    prisma.user.create({
      data: {
        phone: `+9647${tag}1111`,
        name: 'راكبة أولى',
        gender: Gender.FEMALE,
        roles: [UserRole.RIDER],
      },
    }),
    prisma.user.create({
      data: {
        phone: `+9647${tag}2222`,
        name: 'راكبة ثانية',
        gender: Gender.FEMALE,
        roles: [UserRole.RIDER],
      },
    }),
  ]);

  return {
    corridorId: corridor.id,
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    riderAId: riderA.id,
    riderBId: riderB.id,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  const userIds = [f.driverUserId, f.riderAId, f.riderBId];
  await prisma.notification.deleteMany({ where: { userId: { in: userIds } } });
  await prisma.seatBooking.deleteMany({ where: { trip: { corridorId: f.corridorId } } });
  await prisma.trip.deleteMany({ where: { corridorId: f.corridorId } });
  await prisma.vehicle.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.document.deleteMany({ where: { driverId: f.driverProfileId } });
  await prisma.driverProfile.deleteMany({ where: { id: f.driverProfileId } });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  await prisma.corridor.deleteMany({ where: { id: f.corridorId } });
}

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

/** Every notification this user holds, newest first. */
function inbox(userId: string) {
  return prisma.notification.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });
}

async function typesFor(userId: string): Promise<NotificationType[]> {
  return (await inbox(userId)).map((n) => n.type);
}

beforeAll(async () => {
  prisma = new PrismaService();
  await prisma.$connect();

  // A real NotificationService — the point is that the emitter runs for real.
  // FCM is left unconfigured, exactly as in production today, so the push sink
  // logs and the stored sink is what we assert on.
  const config = { get: () => undefined } as unknown as ConfigService;
  const notifications = new NotificationService(prisma, config);
  const drivers = new DriverService(prisma, {} as StorageService);
  const corridors = new CorridorService(prisma);
  trips = new TripService(prisma, drivers, corridors, notifications);
  bookings = new BookingService(prisma, drivers, notifications);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('notification fan-out (real database)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('a driver cancelling a booked trip notifies EVERY booked rider, and not the driver', async () => {
    // The live-testing failure, end to end.
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);
    await book(f.riderBId, trip.id);

    await trips.cancelTrip(f.driverUserId, trip.id);

    expect(await typesFor(f.riderAId)).toContain(NotificationType.TRIP_CANCELLED);
    expect(await typesFor(f.riderBId)).toContain(NotificationType.TRIP_CANCELLED);
    // The driver did the cancelling; telling them about it would be noise, and
    // would put the most alarming message in the inbox of the person who is
    // not alarmed.
    expect(await typesFor(f.driverUserId)).not.toContain(NotificationType.TRIP_CANCELLED);
  });

  it('the cancellation carries the tripId, so the app can name the trip', async () => {
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);

    await trips.cancelTrip(f.driverUserId, trip.id);

    const row = (await inbox(f.riderAId)).find((n) => n.type === NotificationType.TRIP_CANCELLED);
    expect(row?.tripId).toBe(trip.id);
    expect(row?.readAt).toBeNull(); // arrives unread
  });

  it('a rider who never booked hears nothing about the cancellation', async () => {
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);

    await trips.cancelTrip(f.driverUserId, trip.id);

    expect(await typesFor(f.riderBId)).toHaveLength(0);
  });

  it('booking notifies the DRIVER of the booking and the RIDER of the confirmation', async () => {
    const trip = await postTrip(f);

    await book(f.riderAId, trip.id);

    expect(await typesFor(f.driverUserId)).toEqual([NotificationType.BOOKING_CREATED]);
    expect(await typesFor(f.riderAId)).toEqual([NotificationType.BOOKING_CONFIRMED]);
  });

  it('a rider cancelling notifies the driver and leaves the rider a record', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderAId, trip.id);

    await bookings.cancel(f.riderAId, booking.id);

    expect(await typesFor(f.driverUserId)).toContain(
      NotificationType.BOOKING_CANCELLED_BY_RIDER,
    );
    expect(await typesFor(f.riderAId)).toContain(NotificationType.BOOKING_CANCELLED);
    // Distinct types on purpose: "someone pulled out of your trip" and "your
    // booking is cancelled" are different events with different urgency, and
    // one shared type would make them indistinguishable in either inbox.
  });

  it('starting a trip notifies its riders only', async () => {
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);

    await trips.start(f.driverUserId, trip.id);

    expect(await typesFor(f.riderAId)).toContain(NotificationType.TRIP_STARTED);
    expect(await typesFor(f.riderBId)).toHaveLength(0);
  });

  it('completing a trip notifies the riders who rode', async () => {
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);
    await trips.start(f.driverUserId, trip.id);

    await trips.complete(f.driverUserId, trip.id);

    expect(await typesFor(f.riderAId)).toContain(NotificationType.TRIP_COMPLETED);
  });
});

describe('the notification centre (real database)', () => {
  let f: Fixture;
  let notifications: NotificationService;

  beforeEach(async () => {
    f = await seedFixture();
    notifications = new NotificationService(
      prisma,
      { get: () => undefined } as unknown as ConfigService,
    );
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('counts unread, and stops counting once read', async () => {
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id); // → 1 for the rider
    await trips.cancelTrip(f.driverUserId, trip.id); // → 2 for the rider

    const before = await notifications.list(f.riderAId);
    expect(before.unreadCount).toBe(2);
    expect(before.notifications).toHaveLength(2);

    await notifications.markRead(f.riderAId, before.notifications[0].id);
    expect((await notifications.unreadCount(f.riderAId)).unreadCount).toBe(1);

    await notifications.markAllRead(f.riderAId);
    expect((await notifications.unreadCount(f.riderAId)).unreadCount).toBe(0);
  });

  it('mark-all-read leaves OTHER users alone', async () => {
    // A `where` without the userId would clear everyone's badge. A mocked
    // updateMany cannot tell you that; this can.
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);

    await notifications.markAllRead(f.riderAId);

    expect((await notifications.unreadCount(f.driverUserId)).unreadCount).toBe(1);
  });

  it('the list is newest first', async () => {
    const trip = await postTrip(f);
    await book(f.riderAId, trip.id);
    await trips.cancelTrip(f.driverUserId, trip.id);

    const { notifications: rows } = await notifications.list(f.riderAId);

    expect(rows[0].type).toBe(NotificationType.TRIP_CANCELLED);
    expect(rows[1].type).toBe(NotificationType.BOOKING_CONFIRMED);
  });
});
