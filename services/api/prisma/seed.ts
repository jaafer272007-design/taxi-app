import { PrismaClient, UserRole } from '@prisma/client';
import { normalizeIraqiPhone } from '../src/common/phone.util';
import { seedSuperAdmin } from '../src/admin-auth/seed-super-admin';
import { seedCorridorGrid } from '../src/corridor/seed-corridors';

/**
 * Idempotent seed:
 *  - ONE ADMIN user (from ADMIN_PHONE) so admin endpoints are testable. The admin
 *    logs in through the normal WhatsApp OTP flow and receives an ADMIN-role JWT.
 *  - The FULL corridor grid: every ordered pair of the 18 governorate hubs
 *    (18 x 17 = 306), priced from distance. See src/corridor/corridor-grid.ts
 *    for the coordinates and the fare formula. Existing corridors are NEVER
 *    touched, so a price the admin tuned survives every future deploy.
 *
 * Run: ADMIN_PHONE=+9647700000000 npm run prisma:seed
 */
const prisma = new PrismaClient();

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
  const result = await seedCorridorGrid(prisma);
  console.log(
    `✔ Corridors: ${result.created} created, ` +
      `${result.total - result.created} already present (left untouched) — ` +
      `${result.total}/${result.expected} total`,
  );
  if (result.total < result.expected) {
    throw new Error(
      `Corridor grid incomplete: ${result.total} rows, expected ${result.expected}.`,
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
