import { AdminRole } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PasswordService } from './password.service';

/** The slice of PrismaClient this needs — so it is testable without a database. */
export interface AdminUserStore {
  adminUser: {
    findUnique(args: { where: { username: string } }): Promise<{ username: string } | null>;
    create(args: { data: Record<string, unknown> }): Promise<{ username: string }>;
    update(args: {
      where: { username: string };
      data: Record<string, unknown>;
    }): Promise<{ username: string }>;
  };
}

export interface SeedResult {
  username: string;
  created: boolean;
}

/**
 * Creates the ONE super admin from the environment.
 *
 * Idempotent in the way that matters for a credential: re-running it **never
 * rewrites an existing account's password**. If it did, every deploy that ran
 * the seed would silently reset the super admin's password back to whatever the
 * environment happened to hold — undoing any rotation done through the panel,
 * and leaving a stale CI variable as a live way in.
 *
 * The plaintext is read, hashed, and dropped. It is never logged, never stored,
 * and never returned.
 */
export async function seedSuperAdmin(
  store: AdminUserStore,
  env: { SUPER_ADMIN_USERNAME?: string; SUPER_ADMIN_PASSWORD?: string },
): Promise<SeedResult> {
  const username = env.SUPER_ADMIN_USERNAME?.trim().toLowerCase();
  const password = env.SUPER_ADMIN_PASSWORD;

  if (!username || !password) {
    throw new Error(
      'SUPER_ADMIN_USERNAME and SUPER_ADMIN_PASSWORD are required to seed the super admin. ' +
        'See services/api/.env.example.',
    );
  }
  if (password.length < PasswordService.MIN_LENGTH) {
    throw new Error(
      `SUPER_ADMIN_PASSWORD must be at least ${PasswordService.MIN_LENGTH} characters.`,
    );
  }

  const existing = await store.adminUser.findUnique({ where: { username } });

  if (existing) {
    // Re-assert the role and re-enable the account (a locked-out super admin
    // has to have SOME way back), but leave the hash exactly as it is.
    await store.adminUser.update({
      where: { username },
      data: { role: AdminRole.SUPER_ADMIN, active: true },
    });
    return { username, created: false };
  }

  await store.adminUser.create({
    data: {
      username,
      passwordHash: await bcrypt.hash(password, PasswordService.COST),
      role: AdminRole.SUPER_ADMIN,
      active: true,
    },
  });
  return { username, created: true };
}
