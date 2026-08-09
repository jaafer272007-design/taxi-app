import {
  AdminRole,
  DocStatus,
  DocType,
  DriverStatus,
  Gender,
  PrismaClient,
  UserRole,
} from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import Redis from 'ioredis';

import { PasswordService } from '../src/admin-auth/password.service';
import { seedSuperAdmin } from '../src/admin-auth/seed-super-admin';
import { seedCorridorGrid } from '../src/corridor/seed-corridors';

/**
 * Deterministic state for the admin panel's Playwright suite.
 *
 * Separate from `seed.ts` on purpose. The production seed is *additive and
 * non-destructive* — that is its whole point, and it must stay that way. This
 * one is **destructive over a fixed set of rows it owns**, because an E2E suite
 * that approves a driver and creates a corridor has to be able to run twice and
 * get the same answer. It only ever touches records it created itself, keyed by
 * the `e2e-` username prefix and the `+9647999…` phone block.
 *
 * Run against a THROWAWAY database:
 *
 *     DATABASE_URL=... SUPER_ADMIN_USERNAME=... SUPER_ADMIN_PASSWORD=... \
 *       npx ts-node prisma/seed-e2e.ts
 *
 * ## Fixtures are mirrored in `apps/admin/e2e/fixtures.ts`
 *
 * The two files sit in different packages with different toolchains, so the
 * values are written out in both rather than imported across the boundary.
 * Drift is caught immediately rather than silently: `e2e/fixtures.spec.ts`
 * asserts the seeded state matches what the tests expect and names this file in
 * the failure message.
 */

const prisma = new PrismaClient();

/** Password for every account this seed creates. Test-only, never a real one. */
const E2E_PASSWORD = 'e2e-password-1234';

/**
 * Admin accounts. Each login test gets its OWN account because the login
 * throttle keys on username+IP: every Playwright worker shares one IP, so a
 * lockout test that reused a shared username would lock out unrelated tests.
 */
const ADMIN_ACCOUNTS = [
  // The operational admin — used by every spec that needs a signed-in
  // non-super admin. Never used for a failed login.
  { username: 'e2e-admin', role: AdminRole.ADMIN, active: true },
  // Burned by the rate-limit test, which deliberately spends its budget.
  { username: 'e2e-lockout', role: AdminRole.ADMIN, active: true },
  // Gets exactly one wrong-password attempt, to compare the failure message
  // against an unknown username's.
  { username: 'e2e-wrongpass', role: AdminRole.ADMIN, active: true },
  // Disabled: must fail login with the SAME sentence as the other two.
  { username: 'e2e-disabled', role: AdminRole.ADMIN, active: false },
] as const;

/**
 * Corridor pairs the seed DELETES so the panel can create them.
 *
 * The production grid fills all 18x17 = 306 ordered pairs, which means that on
 * a fully seeded database "create a corridor" can only ever produce a duplicate
 * error — there is no free pair left. Holding two back is what makes the
 * create path testable at all.
 */
const RESERVED_FREE_PAIRS = [
  { originCity: 'Duhok', destCity: 'Samawah' },
  { originCity: 'Samawah', destCity: 'Duhok' },
] as const;

/**
 * Corridors reserved for the mutating tests. Reset to known prices/active on
 * every seed so an edit or a toggle from a previous run does not leak forward.
 */
const RESERVED_MUTABLE = [
  // Edited by the "edit a price" test.
  {
    originCity: 'Tikrit',
    destCity: 'Amarah',
    suggestedPricePerSeat: 30000,
    minPricePerSeat: 18000,
    maxPricePerSeat: 48000,
    active: true,
  },
  // Toggled by the "toggle active" test.
  {
    originCity: 'Amarah',
    destCity: 'Tikrit',
    suggestedPricePerSeat: 30000,
    minPricePerSeat: 18000,
    maxPricePerSeat: 48000,
    active: true,
  },
] as const;

/**
 * Drivers, one per mutating action so the tests never contend for a row.
 * Phones live in a reserved +9647999xxxxxx block that nothing else uses.
 */
const DRIVERS = [
  {
    phone: '+9647999000001',
    name: 'سائق الاعتماد',
    status: DriverStatus.PENDING,
    plate: 'E2E-1001',
  },
  {
    phone: '+9647999000002',
    name: 'سائق الرفض',
    status: DriverStatus.PENDING,
    plate: 'E2E-1002',
  },
  {
    phone: '+9647999000003',
    name: 'سائق الإيقاف',
    status: DriverStatus.APPROVED,
    plate: 'E2E-1003',
  },
  {
    phone: '+9647999000004',
    name: 'سائق مرفوض',
    status: DriverStatus.REJECTED,
    plate: 'E2E-1004',
    rejectionReason: 'صورة إجازة السوق غير واضحة.',
  },
  // Never acted on by any test. The status-filter assertions use this one so
  // they hold no matter what order the mutating tests ran in — and, more to the
  // point, so a CI retry of a single test still starts from a known status.
  {
    phone: '+9647999000005',
    name: 'سائق ثابت للفلترة',
    status: DriverStatus.PENDING,
    plate: 'E2E-1005',
  },
] as const;

/**
 * A rider blocked for repeated no-shows.
 *
 * Without this the panel's /no-shows page is an empty state in every run, and
 * "the appeal path works" would be asserted only by unit tests — while the
 * thing that actually has to work is an admin clicking «ألغِ الواقعة» and a
 * rider becoming able to book again.
 *
 * **The dates are relative on purpose.** The rolling window and the cooling-off
 * period are both computed from `now`, so fixed timestamps would quietly stop
 * producing a blocked rider as the calendar moved and the page would go green
 * on an empty table. Three occurrences inside the last week put the count at
 * the default threshold with the block ending ~6 days out, whenever it runs.
 */
const NO_SHOW_RIDER = {
  phone: '+9647999000010',
  name: 'راكب متغيّب',
  /** Days before now. Length must equal the default NO_SHOW_BLOCK_THRESHOLD. */
  daysAgo: [1, 3, 5],
} as const;

async function seedAdminAccounts(): Promise<void> {
  // The role-separation spec creates throwaway accounts to prove the SUPER_ADMIN
  // can (it cannot assert success against a fixture account without changing a
  // credential the rest of the suite depends on). Clear last run's litter.
  const swept = await prisma.adminUser.deleteMany({
    where: { username: { startsWith: 'e2e-throwaway-' } },
  });
  if (swept.count > 0) {
    console.log(`✔ Swept ${swept.count} throwaway admin account(s) from a previous run`);
  }

  const passwordHash = await bcrypt.hash(E2E_PASSWORD, PasswordService.COST);

  for (const account of ADMIN_ACCOUNTS) {
    // Unlike the production super-admin seed, this DOES rewrite the password —
    // these are disposable test accounts whose credentials the suite hardcodes,
    // and a run must not inherit a password some earlier test changed.
    await prisma.adminUser.upsert({
      where: { username: account.username },
      update: { passwordHash, role: account.role, active: account.active },
      create: {
        username: account.username,
        passwordHash,
        role: account.role,
        active: account.active,
      },
    });
  }
  console.log(`✔ Admin accounts: ${ADMIN_ACCOUNTS.map((a) => a.username).join(', ')}`);
}

async function seedCorridors(): Promise<void> {
  const grid = await seedCorridorGrid(prisma);

  // Free the pairs the create tests need. Delete rather than skip-insert: a
  // previous run's created corridor has to go too.
  const freed = await prisma.corridor.deleteMany({
    where: { OR: RESERVED_FREE_PAIRS.map((p) => ({ ...p })) },
  });

  for (const corridor of RESERVED_MUTABLE) {
    const { originCity, destCity, ...values } = corridor;
    await prisma.corridor.update({
      where: { originCity_destCity: { originCity, destCity } },
      data: values,
    });
  }

  const total = await prisma.corridor.count();
  console.log(
    `✔ Corridors: ${total} rows ` +
      `(grid ${grid.expected}, freed ${freed.count} for the create tests, ` +
      `${RESERVED_MUTABLE.length} reset to known values)`,
  );
}

/** Remove a driver and everything hanging off it. No cascade in the schema. */
async function deleteDriverByPhone(phone: string): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { phone },
    include: { driver: true },
  });
  if (!user) return;

  if (user.driver) {
    await prisma.document.deleteMany({ where: { driverId: user.driver.id } });
    await prisma.vehicle.deleteMany({ where: { driverId: user.driver.id } });
    await prisma.driverProfile.delete({ where: { id: user.driver.id } });
  }
  await prisma.user.delete({ where: { id: user.id } });
}

async function seedDrivers(): Promise<void> {
  for (const driver of DRIVERS) {
    // Rebuilt from scratch every run: an approved-then-suspended driver from a
    // previous run must come back as PENDING, and updating in place would leave
    // documents and rejection reasons behind.
    await deleteDriverByPhone(driver.phone);

    await prisma.user.create({
      data: {
        phone: driver.phone,
        name: driver.name,
        gender: Gender.MALE,
        roles: [UserRole.RIDER, UserRole.DRIVER],
        driver: {
          create: {
            status: driver.status,
            rejectionReason: 'rejectionReason' in driver ? driver.rejectionReason : null,
            ratingAvg: 4.5,
            tripsDone: 3,
            vehicle: {
              create: {
                make: 'Toyota',
                model: 'Corolla',
                plate: driver.plate,
                color: 'أبيض',
                seats: 4,
              },
            },
            documents: {
              create: [
                {
                  type: DocType.NATIONAL_ID,
                  url: 'e2e/national-id.jpg',
                  status: DocStatus.PENDING,
                },
                {
                  type: DocType.DRIVING_LICENSE,
                  url: 'e2e/driving-license.jpg',
                  status: DocStatus.PENDING,
                },
              ],
            },
          },
        },
      },
    });
  }
  console.log(`✔ Drivers: ${DRIVERS.length} rebuilt (${DRIVERS.map((d) => d.status).join(', ')})`);
}

/**
 * A live support case: an approved driver, an OPEN trip, and a rider holding a
 * confirmed booking on it.
 *
 * The support spec CANCELS this booking, so it is rebuilt from scratch every
 * run — and the seat count is what the assertion turns on, which is why the
 * trip is created here rather than reused from another fixture that some other
 * spec might book against.
 */
const SUPPORT_CASE = {
  driverPhone: '+9647730000001',
  driverName: 'سائق الدعم',
  riderPhone: '+9647730000002',
  riderName: 'راكب الدعم',
  plate: 'E2E-SUP-1',
  seatsTotal: 4,
  seatCount: 1,
  pricePerSeat: 12000,
} as const;

async function seedSupportCase(): Promise<void> {
  // Rebuilt every run: the spec cancels the booking, and a second run has to
  // start from a bookable trip again.
  for (const phone of [SUPPORT_CASE.driverPhone, SUPPORT_CASE.riderPhone]) {
    const user = await prisma.user.findUnique({
      where: { phone },
      include: { driver: true },
    });
    if (!user) continue;
    if (user.driver) {
      await prisma.seatBooking.deleteMany({
        where: { trip: { driverId: user.driver.id } },
      });
      await prisma.trip.deleteMany({ where: { driverId: user.driver.id } });
      await prisma.earningsRecord.deleteMany({ where: { driverId: user.driver.id } });
      await prisma.vehicle.deleteMany({ where: { driverId: user.driver.id } });
      await prisma.document.deleteMany({ where: { driverId: user.driver.id } });
      await prisma.driverProfile.delete({ where: { id: user.driver.id } });
    }
    await prisma.seatBooking.deleteMany({ where: { riderId: user.id } });
    await prisma.noShowRecord.deleteMany({ where: { riderId: user.id } });
    await prisma.notification.deleteMany({ where: { userId: user.id } });
    await prisma.user.delete({ where: { id: user.id } });
  }
  // The audit log is append-only in production; the seed clears only what
  // previous runs of this suite wrote, so an assertion on "one row" holds.
  await prisma.adminAction.deleteMany({});

  const corridor = await prisma.corridor.findFirstOrThrow({
    where: { originCity: 'Najaf', destCity: 'Karbala' },
  });

  const driver = await prisma.user.create({
    data: {
      phone: SUPPORT_CASE.driverPhone,
      name: SUPPORT_CASE.driverName,
      gender: Gender.MALE,
      roles: [UserRole.RIDER, UserRole.DRIVER],
      driver: {
        create: {
          status: DriverStatus.APPROVED,
          vehicle: {
            create: {
              make: 'Toyota',
              model: 'Corolla',
              plate: SUPPORT_CASE.plate,
              color: 'أبيض',
              seats: SUPPORT_CASE.seatsTotal,
            },
          },
        },
      },
    },
    include: { driver: { include: { vehicle: true } } },
  });

  const rider = await prisma.user.create({
    data: {
      phone: SUPPORT_CASE.riderPhone,
      name: SUPPORT_CASE.riderName,
      gender: Gender.MALE,
      roles: [UserRole.RIDER],
    },
  });

  // Three hours out: comfortably inside every catchability window, and far
  // enough away that the expiry sweep cannot retire it mid-suite.
  const trip = await prisma.trip.create({
    data: {
      corridorId: corridor.id,
      driverId: driver.driver!.id,
      vehicleId: driver.driver!.vehicle!.id,
      departureTime: new Date(Date.now() + 3 * 60 * 60 * 1000),
      seatsTotal: SUPPORT_CASE.seatsTotal,
      seatsAvailable: SUPPORT_CASE.seatsTotal - SUPPORT_CASE.seatCount,
      pricePerSeat: SUPPORT_CASE.pricePerSeat,
    },
  });

  await prisma.seatBooking.create({
    data: {
      tripId: trip.id,
      riderId: rider.id,
      pickupLat: 31.999,
      pickupLng: 44.3148,
      pickupLabel: 'حي السلام',
      dropoffLat: 32.616,
      dropoffLng: 44.0242,
      dropoffLabel: 'قرب المستشفى',
      seatCount: SUPPORT_CASE.seatCount,
      fare: SUPPORT_CASE.pricePerSeat * SUPPORT_CASE.seatCount,
    },
  });

  console.log(
    `✔ Support case: trip with ${SUPPORT_CASE.seatsTotal - SUPPORT_CASE.seatCount} of ` +
      `${SUPPORT_CASE.seatsTotal} seats free, one confirmed booking`,
  );
}

async function seedNoShowRider(): Promise<void> {
  // Rebuilt from scratch: a previous run's spec may have voided a record or
  // lifted the block entirely, and a voided row updated in place would still
  // carry the old admin's reason.
  const existing = await prisma.user.findUnique({
    where: { phone: NO_SHOW_RIDER.phone },
  });
  if (existing) {
    await prisma.noShowRecord.deleteMany({ where: { riderId: existing.id } });
    await prisma.user.delete({ where: { id: existing.id } });
  }

  const rider = await prisma.user.create({
    data: {
      phone: NO_SHOW_RIDER.phone,
      name: NO_SHOW_RIDER.name,
      gender: Gender.FEMALE,
      roles: [UserRole.RIDER],
    },
  });

  const now = Date.now();
  const DAY_MS = 24 * 60 * 60 * 1000;
  await prisma.noShowRecord.createMany({
    data: NO_SHOW_RIDER.daysAgo.map((days, i) => ({
      riderId: rider.id,
      // No relation on these columns (they are context, like Notification's),
      // so synthetic ids are correct here — the panel never joins through them.
      tripId: `e2e-noshow-trip-${i + 1}`,
      bookingId: `e2e-noshow-booking-${i + 1}`,
      seatCount: i + 1,
      createdAt: new Date(now - days * DAY_MS),
    })),
  });

  console.log(
    `✔ No-show rider: ${NO_SHOW_RIDER.name} rebuilt with ` +
      `${NO_SHOW_RIDER.daysAgo.length} occurrence(s) — blocked`,
  );
}

/**
 * Clear the admin-login failure counters.
 *
 * The rate-limit test deliberately spends its account's budget, and the counter
 * lives in Redis with a 15-minute TTL — outliving the run. Without this the
 * suite passes once and then fails on every re-run inside that window, because
 * the first attempt already comes back rate-limited instead of showing the
 * generic failure. CI gets a fresh Redis and would never have shown it.
 */
async function resetLoginThrottle(): Promise<void> {
  const url = process.env.REDIS_URL ?? 'redis://127.0.0.1:6379';
  const redis = new Redis(url, { maxRetriesPerRequest: 3 });
  try {
    const keys = await redis.keys('admin:login:fail:*');
    if (keys.length > 0) {
      await redis.del(...keys);
    }
    console.log(`✔ Login throttle: cleared ${keys.length} counter(s)`);
  } finally {
    await redis.quit();
  }
}

async function main(): Promise<void> {
  const superAdmin = await seedSuperAdmin(prisma, process.env);
  console.log(
    `✔ Super admin: ${superAdmin.username} ` +
      (superAdmin.created ? '(created)' : '(existing — password left unchanged)'),
  );

  await seedAdminAccounts();
  await seedCorridors();
  await seedDrivers();
  await seedNoShowRider();
  await seedSupportCase();
  await resetLoginThrottle();
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
