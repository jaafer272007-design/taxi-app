import * as bcrypt from 'bcryptjs';
import { AdminRole } from '@prisma/client';
import { seedSuperAdmin, AdminUserStore } from './seed-super-admin';

const ENV = { SUPER_ADMIN_USERNAME: 'superadmin', SUPER_ADMIN_PASSWORD: 'a-strong-password' };

function store(existing: { username: string } | null = null) {
  return {
    adminUser: {
      findUnique: jest.fn().mockResolvedValue(existing),
      create: jest.fn().mockImplementation(async ({ data }: any) => data),
      update: jest.fn().mockImplementation(async ({ data }: any) => data),
    },
  };
}

describe('seedSuperAdmin', () => {
  it('creates the super admin on a fresh database, with a bcrypt hash', async () => {
    const db = store(null);

    const result = await seedSuperAdmin(db as unknown as AdminUserStore, ENV);

    expect(result).toEqual({ username: 'superadmin', created: true });
    const { data } = db.adminUser.create.mock.calls[0][0];
    expect(data.role).toBe(AdminRole.SUPER_ADMIN);
    expect(data.active).toBe(true);
    expect(data.passwordHash).toMatch(/^\$2[aby]\$/);
    // The plaintext is hashed and dropped — it is never stored as given.
    expect(data.passwordHash).not.toContain('a-strong-password');
    await expect(bcrypt.compare('a-strong-password', data.passwordHash as string)).resolves.toBe(
      true,
    );
  });

  it('is idempotent — a second run creates nothing', async () => {
    const db = store({ username: 'superadmin' });

    const result = await seedSuperAdmin(db as unknown as AdminUserStore, ENV);

    expect(result).toEqual({ username: 'superadmin', created: false });
    expect(db.adminUser.create).not.toHaveBeenCalled();
  });

  it('NEVER rewrites an existing password', async () => {
    // The important half of idempotency. If re-seeding reset the hash, every
    // deploy would silently roll the super admin's password back to whatever
    // the environment held — undoing rotation and leaving a stale CI variable
    // as a live way in.
    const db = store({ username: 'superadmin' });

    await seedSuperAdmin(db as unknown as AdminUserStore, {
      ...ENV,
      SUPER_ADMIN_PASSWORD: 'a-completely-different-password',
    });

    const { data } = db.adminUser.update.mock.calls[0][0];
    expect(data).not.toHaveProperty('passwordHash');
    expect(data).toEqual({ role: AdminRole.SUPER_ADMIN, active: true });
  });

  it('re-enables a disabled super admin so there is always a way back in', async () => {
    const db = store({ username: 'superadmin' });

    await seedSuperAdmin(db as unknown as AdminUserStore, ENV);

    expect(db.adminUser.update.mock.calls[0][0].data.active).toBe(true);
  });

  it('lower-cases and trims the configured username', async () => {
    const db = store(null);

    await seedSuperAdmin(db as unknown as AdminUserStore, {
      ...ENV,
      SUPER_ADMIN_USERNAME: '  SuperAdmin  ',
    });

    expect(db.adminUser.findUnique).toHaveBeenCalledWith({ where: { username: 'superadmin' } });
    expect(db.adminUser.create.mock.calls[0][0].data.username).toBe('superadmin');
  });

  it('refuses to run without both env vars', async () => {
    await expect(seedSuperAdmin(store() as unknown as AdminUserStore, {})).rejects.toThrow(
      /SUPER_ADMIN_USERNAME and SUPER_ADMIN_PASSWORD/,
    );
    await expect(
      seedSuperAdmin(store() as unknown as AdminUserStore, {
        SUPER_ADMIN_USERNAME: 'superadmin',
      }),
    ).rejects.toThrow(/SUPER_ADMIN_USERNAME and SUPER_ADMIN_PASSWORD/);
  });

  it('refuses a password below the policy minimum', async () => {
    const db = store(null);

    await expect(
      seedSuperAdmin(db as unknown as AdminUserStore, { ...ENV, SUPER_ADMIN_PASSWORD: 'short' }),
    ).rejects.toThrow(/at least/);
    expect(db.adminUser.create).not.toHaveBeenCalled();
  });

  it('never puts the password in its error messages', async () => {
    const secret = 'tiny';
    const message = await seedSuperAdmin(store(null) as unknown as AdminUserStore, {
      ...ENV,
      SUPER_ADMIN_PASSWORD: secret,
    }).catch((e: Error) => e.message);

    expect(message).not.toContain(secret);
  });
});
