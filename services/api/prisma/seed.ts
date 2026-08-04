import { PrismaClient, UserRole } from '@prisma/client';
import { normalizeIraqiPhone } from '../src/common/phone.util';
import { seedSuperAdmin } from '../src/admin-auth/seed-super-admin';

/**
 * Idempotent seed:
 *  - ONE ADMIN user (from ADMIN_PHONE) so admin endpoints are testable. The admin
 *    logs in through the normal WhatsApp OTP flow and receives an ADMIN-role JWT.
 *  - A few real corridors (both directions) with a placeholder price band so
 *    multi-corridor search is testable: Najaf↔Karbala, Najaf↔Baghdad,
 *    Karbala↔Baghdad. Admin sets real prices / adds more via /corridors.
 *
 * Run: ADMIN_PHONE=+9647700000000 npm run prisma:seed
 */
const prisma = new PrismaClient();

// Placeholder pricing in IQD (integers). The driver picks the actual price per
// seat inside [MIN, MAX]; SUGGESTED is what the post-a-trip form prefills.
// Same 50% / 200% band the driver-set-pricing migration backfills with, so a
// freshly seeded database and a migrated one behave identically.
const PLACEHOLDER_SUGGESTED_PRICE_IQD = 5000;
const PLACEHOLDER_MIN_PRICE_IQD = 2500;
const PLACEHOLDER_MAX_PRICE_IQD = 10000;
const CORRIDORS = [
  { originCity: 'Najaf', destCity: 'Karbala' },
  { originCity: 'Karbala', destCity: 'Najaf' },
  { originCity: 'Najaf', destCity: 'Baghdad' },
  { originCity: 'Baghdad', destCity: 'Najaf' },
  { originCity: 'Karbala', destCity: 'Baghdad' },
  { originCity: 'Baghdad', destCity: 'Karbala' },
];

async function seedAdmin() {
  const raw = process.env.ADMIN_PHONE;
  if (!raw) {
    throw new Error('ADMIN_PHONE env var is required to seed the admin user.');
  }
  const phone = normalizeIraqiPhone(raw);
  if (!phone) {
    throw new Error(`ADMIN_PHONE "${raw}" is not a valid Iraqi (+964) mobile number.`);
  }

  const existing = await prisma.user.findUnique({ where: { phone } });
  const roles = Array.from(new Set([...(existing?.roles ?? []), UserRole.ADMIN]));

  const admin = await prisma.user.upsert({
    where: { phone },
    update: { roles: { set: roles } },
    create: { phone, name: 'Admin', roles },
  });
  console.log(`✔ Admin: ${admin.phone} (roles: ${admin.roles.join(', ')})`);
}

async function seedCorridors() {
  for (const c of CORRIDORS) {
    // Idempotent via the (originCity, destCity) unique index. `update: {}` keeps
    // any admin-adjusted pricing on re-seed.
    const corridor = await prisma.corridor.upsert({
      where: {
        originCity_destCity: { originCity: c.originCity, destCity: c.destCity },
      },
      update: {},
      create: {
        originCity: c.originCity,
        destCity: c.destCity,
        suggestedPricePerSeat: PLACEHOLDER_SUGGESTED_PRICE_IQD,
        minPricePerSeat: PLACEHOLDER_MIN_PRICE_IQD,
        maxPricePerSeat: PLACEHOLDER_MAX_PRICE_IQD,
        active: true,
      },
    });
    console.log(
      `✔ Corridor ${corridor.originCity}→${corridor.destCity} ` +
        `(suggested ${corridor.suggestedPricePerSeat} IQD, ` +
        `allowed ${corridor.minPricePerSeat}–${corridor.maxPricePerSeat})`,
    );
  }
}

async function main() {
  await seedAdmin();

  // The logic lives in src/ so it can be unit-tested; here we just wire it to
  // the real client and the process environment.
  const superAdmin = await seedSuperAdmin(prisma, process.env);
  console.log(
    `✔ Super admin: ${superAdmin.username} ` +
      (superAdmin.created ? '(created)' : '(existing — password left unchanged)'),
  );

  await seedCorridors();
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
