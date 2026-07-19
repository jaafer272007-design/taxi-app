import { PrismaClient, UserRole } from '@prisma/client';
import { normalizeIraqiPhone } from '../src/common/phone.util';

/**
 * Idempotent seed:
 *  - ONE ADMIN user (from ADMIN_PHONE) so admin endpoints are testable. The admin
 *    logs in through the normal WhatsApp OTP flow and receives an ADMIN-role JWT.
 *  - A few real corridors (both directions) with a placeholder price so
 *    multi-corridor search is testable: Najaf↔Karbala, Najaf↔Baghdad,
 *    Karbala↔Baghdad. Admin sets real prices / adds more via /corridors.
 *
 * Run: ADMIN_PHONE=+9647700000000 npm run prisma:seed
 */
const prisma = new PrismaClient();

// Placeholder fare in IQD (integer). Admin adjusts it later.
const PLACEHOLDER_PRICE_IQD = 5000;
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
    // any admin-adjusted price on re-seed.
    const corridor = await prisma.corridor.upsert({
      where: {
        originCity_destCity: { originCity: c.originCity, destCity: c.destCity },
      },
      update: {},
      create: {
        originCity: c.originCity,
        destCity: c.destCity,
        pricePerSeat: PLACEHOLDER_PRICE_IQD,
        active: true,
      },
    });
    console.log(
      `✔ Corridor ${corridor.originCity}→${corridor.destCity} (${corridor.pricePerSeat} IQD)`,
    );
  }
}

async function main() {
  await seedAdmin();
  await seedCorridors();
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
