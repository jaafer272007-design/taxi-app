import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DriverStatus, Gender, UserRole } from '@prisma/client';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import { CorridorService } from '../corridor/corridor.service';
import { DriverService } from '../driver/driver.service';
import { NotificationService } from '../notification/notification.service';
import { StorageService } from '../storage/storage.service';
import { OtpService } from './otp.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { TripService } from '../trip/trip.service';
import { TripContactService } from '../trip/trip-contact.service';
import { BookingService } from '../booking/booking.service';
import { NoShowService } from '../booking/no-show.service';
import { AuthService } from './auth.service';

/**
 * جهة اتصال الطوارئ — الحدّ الذي يجب ألّا تعبره، مقيساً لا موثوقاً به.
 *
 * ## لماذا تكامل، ولماذا بالبحث عن النص لا بفحص الحقول
 *
 * الحمولات اليوم كلها `select` صريح، فالحقل لا يتسرّب. لكن هذا **ليس ضماناً
 * دائماً**: `include: { rider: true }` واحدة بأي مسار مستقبلي تُلحق صفّ
 * المستخدم كاملاً — ومعه الرقم — بلا أن يفشل أي اختبار وحدة، لأن اختبار
 * الوحدة يفحص الموك لا الاستعلام.
 *
 * لذلك تسأل هذه الاختبارات السؤال الصحيح: **هل يظهر هذا الرقم في أي بايت
 * يستلمه السائق؟** تُسلسَل الاستجابة وتُفتَّش نصّياً، بنفس منطق
 * `admin/e2e/security.spec.ts` مع بصمة bcrypt. رقم فريد لكل تشغيل حتى لا
 * يتصادف مع بيانات أخرى.
 *
 * Requires DATABASE_URL. Run with `npm run test:int`.
 */

const MINUTE = 60_000;

let prisma: PrismaService;
let auth: AuthService;
let trips: TripService;
let bookings: BookingService;
let contacts: TripContactService;

interface Fixture {
  corridorId: string;
  driverProfileId: string;
  driverUserId: string;
  riderId: string;
  /** The rider's saved emergency-contact number — the needle in every search. */
  emergencyPhone: string;
  emergencyName: string;
}

async function seedFixture(): Promise<Fixture> {
  // REAL Iraqi mobiles (+9647 + 9 digits), unlike the other int-specs' +9649…
  // placeholders: the emergency contact goes through normalizeIraqiPhone, so a
  // fixture that is not a valid number tests the validator instead of the rule.
  const tag = Math.floor(10000 + Math.random() * 89999).toString();

  const corridor = await prisma.corridor.create({
    data: {
      originCity: `EC-${tag}-A`,
      destCity: `EC-${tag}-B`,
      suggestedPricePerSeat: 10000,
      minPricePerSeat: 5000,
      maxPricePerSeat: 20000,
      active: true,
    },
  });

  const driverUser = await prisma.user.create({
    data: {
      phone: `+96477${tag}000`,
      name: 'سائق الرحلة',
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: `EC-${tag}`,
              color: 'أبيض',
              seats: 4,
            },
          },
        },
      },
    },
    include: { driver: true },
  });

  const rider = await prisma.user.create({
    data: {
      phone: `+96477${tag}111`,
      name: 'راكبة',
      gender: Gender.FEMALE,
      roles: [UserRole.RIDER],
    },
  });

  return {
    corridorId: corridor.id,
    driverProfileId: driverUser.driver!.id,
    driverUserId: driverUser.id,
    riderId: rider.id,
    emergencyPhone: `+96477${tag}999`,
    emergencyName: 'أم علي',
  };
}

async function dropFixture(f: Fixture): Promise<void> {
  const userIds = [f.driverUserId, f.riderId];
  await prisma.noShowRecord.deleteMany({ where: { riderId: { in: userIds } } });
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
    pickup: { lat: 32.0, lng: 44.3, label: 'حي السلام' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'قرب المستشفى' },
    seatCount: 1,
  });
}

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
  contacts = new TripContactService(prisma, drivers);
  auth = new AuthService(
    prisma,
    {} as OtpService,
    {} as WhatsappService,
    {} as JwtService,
  );
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('the emergency contact is optional, and stays the rider’s own', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('is null until the rider sets one — nothing is enabled by default', async () => {
    const me = await auth.me(f.riderId);
    expect(me.emergencyContact).toBeNull();
  });

  it('round-trips a saved contact, normalising a local 0770… number', async () => {
    const local = `0${f.emergencyPhone.slice(4)}`; // +9647… → 07…
    const saved = await auth.updateMe(f.riderId, {
      emergencyContact: { name: `  ${f.emergencyName}  `, phone: local },
    });

    // Normalised on the way in, so the app never has to guess which form it
    // stored — `tel:` gets E.164 whether the rider typed 0770… or +964770….
    expect(saved.emergencyContact).toEqual({
      name: f.emergencyName,
      phone: f.emergencyPhone,
    });
    expect((await auth.me(f.riderId)).emergencyContact).toEqual(saved.emergencyContact);
  });

  it('clears both columns on null, and leaves the profile otherwise intact', async () => {
    await auth.updateMe(f.riderId, {
      emergencyContact: { name: f.emergencyName, phone: f.emergencyPhone },
    });

    const cleared = await auth.updateMe(f.riderId, { emergencyContact: null });

    expect(cleared.emergencyContact).toBeNull();
    expect(cleared.name).toBe('راكبة');
    // Neither column left behind: a half-cleared row is the "name but no
    // number" state the serialiser has to defend against.
    const row = await prisma.user.findUnique({ where: { id: f.riderId } });
    expect(row?.emergencyContactName).toBeNull();
    expect(row?.emergencyContactPhone).toBeNull();
  });

  it('leaves a saved contact alone when the update is about something else', async () => {
    await auth.updateMe(f.riderId, {
      emergencyContact: { name: f.emergencyName, phone: f.emergencyPhone },
    });

    const renamed = await auth.updateMe(f.riderId, { name: 'راكبة أخرى' });

    // Absent ≠ null. An edit-name screen that omits the field must not wipe a
    // safety setting the rider never touched.
    expect(renamed.emergencyContact?.phone).toBe(f.emergencyPhone);
  });

  it('refuses a non-Iraqi number in Arabic', async () => {
    await expect(
      auth.updateMe(f.riderId, {
        emergencyContact: { name: f.emergencyName, phone: '12345' },
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses the rider’s own number — it would dial itself', async () => {
    const own = (await prisma.user.findUnique({ where: { id: f.riderId } }))!.phone;
    await expect(
      auth.updateMe(f.riderId, { emergencyContact: { name: 'أنا', phone: own } }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('it never reaches the driver', () => {
  let f: Fixture;
  let tripId: string;
  let bookingId: string;

  beforeEach(async () => {
    f = await seedFixture();
    await auth.updateMe(f.riderId, {
      emergencyContact: { name: f.emergencyName, phone: f.emergencyPhone },
    });
    const trip = await postTrip(f);
    tripId = trip.id;
    bookingId = (await book(f.riderId, tripId)).id;
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  /**
   * Serialise and search the raw text.
   *
   * A field-by-field assertion would only cover the fields we thought of; this
   * catches the whole class — including a nested user row that arrives by
   * accident through an `include`.
   */
  const leaks = (payload: unknown, needle: string) => JSON.stringify(payload).includes(needle);

  it('is absent from the driver’s bookings list for the trip', async () => {
    const list = await trips.listBookings(f.driverUserId, tripId);

    expect(list).toHaveLength(1);
    expect(leaks(list, f.emergencyPhone)).toBe(false);
    expect(leaks(list, f.emergencyName)).toBe(false);
    // The control: the rider's OWN name is supposed to be there, so a false
    // negative from an empty payload cannot pass this test.
    expect(leaks(list, 'راكبة')).toBe(true);
  });

  it('is absent from the contacts endpoint, which does hand over a real number', async () => {
    const forDriver = await contacts.listContacts(f.driverUserId, tripId);

    // This is the one endpoint in the server that returns a phone number at
    // all, which makes it the likeliest place for a second one to be added.
    expect(leaks(forDriver, f.emergencyPhone)).toBe(false);
    const riderOwnPhone = (await prisma.user.findUnique({ where: { id: f.riderId } }))!.phone;
    expect(leaks(forDriver, riderOwnPhone)).toBe(true);
  });

  it('is absent from the driver’s own trip list', async () => {
    const mine = await trips.listMine(f.driverUserId);
    expect(leaks(mine, f.emergencyPhone)).toBe(false);
  });

  it('is absent from search results, which any rider can call', async () => {
    const results = await bookings.search({ corridorId: f.corridorId });
    expect(leaks(results, f.emergencyPhone)).toBe(false);
  });

  it('is absent from the rider’s OWN bookings list too', async () => {
    // Not a boundary — it is their own data — but /bookings/mine is a list
    // payload that grows, and the contact belongs to the profile endpoint. Two
    // places to change it is how one of them goes stale.
    const mine = await bookings.listMine(f.riderId);

    expect(mine).toHaveLength(1);
    expect(leaks(mine, f.emergencyPhone)).toBe(false);
    expect(mine[0].id).toBe(bookingId);
  });

  it('reaches exactly one caller: the rider asking about themselves', async () => {
    const me = await auth.me(f.riderId);
    expect(me.emergencyContact).toEqual({
      name: f.emergencyName,
      phone: f.emergencyPhone,
    });

    // And the driver asking about themselves gets their own null, not hers.
    const driverMe = await auth.me(f.driverUserId);
    expect(driverMe.emergencyContact).toBeNull();
  });
});

describe('the share message has everything it needs from one call', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = await seedFixture();
  });
  afterEach(async () => {
    await dropFixture(f);
  });

  it('carries the plate, the car, the driver and the trip status', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);

    const [mine] = await bookings.listMine(f.riderId);

    // The plate is the whole point of sharing: it is what lets someone at the
    // other end pick this car out of a rank. A missing one makes the message
    // decorative.
    expect(mine.vehicle).toEqual({
      make: 'Toyota',
      model: 'Corolla',
      plate: expect.stringContaining('EC-'),
      color: 'أبيض',
    });
    expect(mine.driverName).toBe('سائق الرحلة');
    // The emergency action keys off this, so it has to travel with the booking
    // rather than being inferred from the clock — the departNow trap.
    expect(mine.trip.status).toBe('OPEN');
  });

  it('reports EN_ROUTE once the driver starts, which is what unlocks the call', async () => {
    const trip = await postTrip(f);
    await book(f.riderId, trip.id);
    await trips.start(f.driverUserId, trip.id);

    const [mine] = await bookings.listMine(f.riderId);
    expect(mine.trip.status).toBe('EN_ROUTE');
  });
});
