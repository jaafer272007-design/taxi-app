import { PrismaClient, UserRole } from '@prisma/client';
import { normalizeIraqiPhone } from '../src/common/phone.util';

/**
 * Seeds ONE ADMIN user so admin endpoints are testable. The admin logs in
 * through the normal WhatsApp OTP flow (/auth/request-otp → /auth/verify-otp)
 * and receives a JWT carrying the ADMIN role.
 *
 * Run: ADMIN_PHONE=+9647700000000 npm run prisma:seed
 */
const prisma = new PrismaClient();

async function main() {
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

  console.log(`✔ Seeded ADMIN user: ${admin.phone} (roles: ${admin.roles.join(', ')})`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
