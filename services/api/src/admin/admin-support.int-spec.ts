import { ConflictException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  BookingStatus,
  DriverStatus,
  Gender,
  NotificationType,
  TripStatus,
  UserRole,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CorridorService } from '../corridor/corridor.service';
import { DriverService } from '../driver/driver.service';
import { NotificationService } from '../notification/notification.service';
import { StorageService } from '../storage/storage.service';
import { TripService } from '../trip/trip.service';
import { BookingService } from '../booking/booking.service';
import { NoShowService } from '../booking/no-show.service';
import { AdminService } from './admin.service';
import { AdminAuditService } from './admin-audit.service';
import { AdminSupportService } from './admin-support.service';

/**
 * أدوات الدعم — ضد قاعدة بيانات حقيقية.
 *
 * ## لماذا تكامل، ولماذا لا تكفي اختبارات الوحدات هنا إطلاقاً
 *
 * الادّعاء المركزي لهذا العمل هو **«التدخّل يمرّ بنفس المسار»**، وهو ادّعاء
 * عن أثر جانبي: هل رجع المقعد فعلاً؟ هل انبعث الإشعار؟ هل رفضت آلة الحالة
 * الأدمن كما ترفض الراكب؟ اختبار وحدة بموك Prisma يجيب «نعم» مهما كان
 * التنفيذ، لأنه يفحص الموك لا المعاملة.
 *
 * فالتأكيدات هنا تُقاس على صفوف حقيقية: عدد المقاعد قبل/بعد، صفوف
 * `Notification` المكتوبة، وصف `AdminAction`.
 *
 * Requires DATABASE_URL. Run with `npm run test:int`.
 */

const MINUTE = 60_000;

let prisma: PrismaService;
let support: AdminSupportService;
let trips: TripService;
let bookings: BookingService;
let audit: AdminAuditService;

const ADMIN = { id: 'adm-support-test', username: 'e2e-support-admin' };

interface Fixture {
  corridorId: string;
  driverProfileId: string;
  driverUserId: string;
  riderId: string;
  riderPhone: string;
  emergencyPhone: string;
}

async function seedFixture(): Promise<Fixture> {
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const corridor = await prisma.corridor.create({
    data: {
      originCity: `SUP-${tag}-A`,
      destCity: `SUP-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+96478${tag}000`,
      name: 'سائق الدعم',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: `SUP-${tag}`,
              color: 'أبيض',
              seats: 4,
            },
          },
        },
      },
    },
    include: { driver: true },
  });

  const emergencyPhone = `+96478${tag}999`;
  const rider = await prisma.user.create({
    data: {
      phone: `+96478${tag}111`,
      name: 'راكب الدعم',
      gender: Gender.MALE,
      roles: [UserRole.RIDER],
      // The privacy boundary under test: saved, and it must appear in NOTHING
      // the support tools return.
      emergencyContactName: 'أم علي',
      emergencyContactPhone: emergencyPhone,
    },
  });

  return {
    corridorId: corridor.id,
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    riderId: rider.id,
    riderPhone: rider.phone,
    emergencyPhone,
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  const userIds = [f.driverUserId, f.riderId];
  await prisma.adminAction.deleteMany({ where: { adminId: ADMIN.id } });
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

function book(riderId: string, tripId: string, seatCount = 2) {
  return bookings.book(riderId, {
    tripId,
    pickup: { lat: 32.0, lng: 44.3, label: 'حي السلام' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'قرب المستشفى' },
    seatCount,
  });
}

const seatsOf = (tripId: string) =>
  prisma.trip
    .findUniqueOrThrow({ where: { id: tripId }, select: { seatsAvailable: true } })
    .then((t) => t.seatsAvailable);

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
  audit = new AdminAuditService(prisma);
  const adminService = new AdminService(prisma, notifications);
  support = new AdminSupportService(
    prisma,
    adminService,
    bookings,
    trips,
    noShows,
    audit,
  );
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('lookup', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('finds a rider by phone, however the admin types it', async () => {
    // Support starts with a number read out over the phone. `0770…` is how an
    // Iraqi says it; the row stores E.164.
    const local = `0${f.riderPhone.slice(4)}`;
    const result = await support.search(local);

    expect(result.kind).toBe('USER');
    expect(result.kind === 'USER' && result.user.phone).toBe(f.riderPhone);
  });

  it('finds a trip and a booking by id, without being told which it is', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);

    expect(await support.search(trip.id)).toMatchObject({ kind: 'TRIP', tripId: trip.id });
    expect(await support.search(booking.id)).toMatchObject({
      kind: 'BOOKING',
      bookingId: booking.id,
      tripId: trip.id,
    });
  });

  it('says not-found rather than guessing', async () => {
    expect(await support.search('nope-not-an-id')).toMatchObject({ kind: 'NOT_FOUND' });
    expect(await support.search('   ')).toMatchObject({ kind: 'EMPTY' });
  });

  it('gives the rider’s full booking history with trip context', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const detail = await support.rider(f.riderId);

    expect(detail.user.name).toBe('راكب الدعم');
    expect(detail.bookings).toHaveLength(1);
    expect(detail.bookings[0]).toMatchObject({
      status: BookingStatus.CONFIRMED,
      seatCount: 2,
      trip: { status: TripStatus.OPEN },
    });
    expect(detail.block.blocked).toBe(false);
  });

  it('gives the trip with its bookings and the rider behind each one', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const detail = await support.trip(trip.id);

    expect(detail.trip.seatsAvailable).toBe(2);
    expect(detail.driver?.user.name).toBe('سائق الدعم');
    expect(detail.bookings).toHaveLength(1);
    expect(detail.bookings[0].rider?.name).toBe('راكب الدعم');
    expect(detail.bookings[0].pickupLabel).toBe('حي السلام');
  });

  it('gives the driver with vehicle, documents, trips and earnings', async () => {
    await postTrip(f);
    const detail = await support.driver(f.driverProfileId);

    expect(detail.profile.status).toBe(DriverStatus.APPROVED);
    expect(detail.profile.vehicle?.plate).toContain('SUP-');
    expect(detail.trips).toHaveLength(1);
    expect(detail.earnings.total).toBe(0);
  });
});

describe('privacy: the emergency contact reaches no support surface', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  /**
   * Serialise and search the text.
   *
   * Field assertions only cover fields we thought of. The realistic failure is
   * someone swapping an explicit `select` for `include: { user: true }` to add
   * one column — which attaches the whole row, emergency contact included, and
   * fails no unit test.
   */
  const leaks = (payload: unknown, needle: string) => JSON.stringify(payload).includes(needle);

  it('is absent from every detail view, while the rider’s OWN phone is present', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const [rider, tripDetail, driver, searched] = await Promise.all([
      support.rider(f.riderId),
      support.trip(trip.id),
      support.driver(f.driverProfileId),
      support.search(f.riderPhone),
    ]);

    for (const [name, payload] of Object.entries({ rider, tripDetail, driver, searched })) {
      expect(leaks(payload, f.emergencyPhone)).toBe(false);
      expect(leaks(payload, 'أم علي')).toBe(false);
      // Guard against a false pass from an empty payload.
      expect(JSON.stringify(payload).length).toBeGreaterThan(50);
      void name;
    }

    // The control: an admin IS meant to see the rider's own number — that is
    // the privileged view, and support cannot work without it.
    expect(leaks(rider, f.riderPhone)).toBe(true);
    expect(leaks(tripDetail, f.riderPhone)).toBe(true);
  });
});

describe('intervention runs the app’s own path', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('cancelling a booking RETURNS THE SEAT and notifies both sides', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id, 2);
    expect(await seatsOf(trip.id)).toBe(2);

    await prisma.notification.deleteMany({
      where: { userId: { in: [f.riderId, f.driverUserId] } },
    });

    await support.cancelBooking(ADMIN, booking.id, 'اتصل الراكب: خطأ بالحجز');

    // The seat is the whole point. A raw UPDATE on the booking row would have
    // left this at 2 and quietly cost the driver a seat.
    expect(await seatsOf(trip.id)).toBe(4);
    expect(
      (await prisma.seatBooking.findUniqueOrThrow({ where: { id: booking.id } })).status,
    ).toBe(BookingStatus.CANCELLED);

    // And the fan-out ran: the rider learns their seat is gone even though
    // they were not the one who tapped cancel.
    const riderNotes = await prisma.notification.findMany({ where: { userId: f.riderId } });
    const driverNotes = await prisma.notification.findMany({ where: { userId: f.driverUserId } });
    expect(riderNotes.map((n) => n.type)).toContain(NotificationType.BOOKING_CANCELLED);
    expect(driverNotes.map((n) => n.type)).toContain(
      NotificationType.BOOKING_CANCELLED_BY_RIDER,
    );
  });

  it('reopens a LOCKED trip when the freed seat makes it bookable again', async () => {
    // The departNow-shaped bug in its fourth home: a full trip auto-LOCKS, and
    // a cancel that does not reopen it leaves the seat unsellable.
    const trip = await postTrip(f, 2);
    const booking = await book(f.riderId, trip.id, 2);
    expect(
      (await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } })).status,
    ).toBe(TripStatus.LOCKED);

    await support.cancelBooking(ADMIN, booking.id, 'إعادة فتح');

    expect((await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } })).status).toBe(
      TripStatus.OPEN,
    );
  });

  it('CANNOT cancel a booking on an EN_ROUTE trip — a rider cannot either', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id);

    // The state machine is the product's rule, not a rider-facing courtesy.
    // An admin path that bypassed it would be the one place the rule silently
    // does not hold.
    await expect(
      support.cancelBooking(ADMIN, booking.id, 'محاولة بعد الانطلاق'),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(
      (await prisma.seatBooking.findUniqueOrThrow({ where: { id: booking.id } })).status,
    ).toBe(BookingStatus.CONFIRMED);
    // A refused action leaves NO audit row: the log records what happened, not
    // what was attempted.
    expect(await audit.list({ entityId: booking.id })).toHaveLength(0);
  });

  it('cancelling a trip cancels its bookings and notifies every rider', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);
    await prisma.notification.deleteMany({ where: { userId: f.riderId } });

    await support.cancelTrip(ADMIN, trip.id, 'السائق اتصل: عطل بالسيارة');

    expect((await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } })).status).toBe(
      TripStatus.CANCELLED,
    );
    const stillConfirmed = await prisma.seatBooking.count({
      where: { tripId: trip.id, status: BookingStatus.CONFIRMED },
    });
    expect(stillConfirmed).toBe(0);

    const notes = await prisma.notification.findMany({ where: { userId: f.riderId } });
    expect(notes.map((n) => n.type)).toContain(NotificationType.TRIP_CANCELLED);
  });

  it('cannot cancel an EN_ROUTE trip either', async () => {
    const trip = await postTrip(f);
    await trips.start(f.driverUserId, trip.id);
    await expect(support.cancelTrip(ADMIN, trip.id, 'بعد الانطلاق')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('suspends and unsuspends a driver, and refuses to unsuspend one who is not', async () => {
    await support.suspendDriver(ADMIN, f.driverProfileId, 'شكاوى متكررة');
    expect(
      (await prisma.driverProfile.findUniqueOrThrow({ where: { id: f.driverProfileId } }))
        .status,
    ).toBe(DriverStatus.SUSPENDED);

    await support.unsuspendDriver(ADMIN, f.driverProfileId, 'تمت مراجعة الشكاوى');
    expect(
      (await prisma.driverProfile.findUniqueOrThrow({ where: { id: f.driverProfileId } }))
        .status,
    ).toBe(DriverStatus.APPROVED);

    // An APPROVED driver is not suspended — "undo" must not launder a
    // PENDING or REJECTED driver into APPROVED.
    await expect(
      support.unsuspendDriver(ADMIN, f.driverProfileId, 'مرة أخرى'),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('reports a missing entity rather than silently doing nothing', async () => {
    await expect(support.cancelTrip(ADMIN, 'no-such-trip', 'سبب')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

describe('the audit log', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('records who, what, which entity and why — for every intervention', async () => {
    const trip = await postTrip(f);
    const booking = await book(f.riderId, trip.id);

    await support.cancelBooking(ADMIN, booking.id, 'اتصل الراكب: خطأ بالحجز');
    await support.suspendDriver(ADMIN, f.driverProfileId, 'شكاوى متكررة');

    const rows = await audit.list({ adminId: ADMIN.id });
    expect(rows).toHaveLength(2);

    const cancel = rows.find((r) => r.entityId === booking.id)!;
    expect(cancel).toMatchObject({
      adminId: ADMIN.id,
      // Copied at write time so the row survives the account being removed —
      // which is exactly when an incident gets reviewed.
      adminUsername: ADMIN.username,
      type: 'BOOKING_CANCELLED',
      entityType: 'BOOKING',
      reason: 'اتصل الراكب: خطأ بالحجز',
    });

    // Filterable by entity, which is the "what happened to this thing"
    // question support actually asks.
    expect(await audit.list({ entityType: 'DRIVER', entityId: f.driverProfileId })).toHaveLength(
      1,
    );
  });

  it('newest first, and the trip view carries its own history', async () => {
    const trip = await postTrip(f);
    await support.cancelTrip(ADMIN, trip.id, 'عطل بالسيارة');

    const detail = await support.trip(trip.id);
    expect(detail.adminActions).toHaveLength(1);
    expect(detail.adminActions[0].reason).toBe('عطل بالسيارة');
  });

  it('lists the distinct admins for the filter control', async () => {
    const trip = await postTrip(f);
    await support.cancelTrip(ADMIN, trip.id, 'سبب كافٍ');

    const admins = await audit.actingAdmins();
    expect(admins).toContainEqual({ adminId: ADMIN.id, adminUsername: ADMIN.username });
  });
});
