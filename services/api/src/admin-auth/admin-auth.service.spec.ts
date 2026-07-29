import { HttpException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AdminRole } from '@prisma/client';
import { AdminAuthService } from './admin-auth.service';
import { LoginThrottleService } from './login-throttle.service';
import { PasswordService } from './password.service';
import { PrismaService } from '../prisma/prisma.service';
import { ADMIN_TOKEN_KIND } from '../auth/admin-principal';

const IP = '10.0.0.7';
const PASSWORD = 'correct-horse-battery';

describe('AdminAuthService (login)', () => {
  let prisma: { adminUser: { findUnique: jest.Mock } };
  let jwt: { signAsync: jest.Mock };
  let throttle: {
    assertNotLockedOut: jest.Mock;
    recordFailure: jest.Mock;
    clear: jest.Mock;
  };
  let passwords: PasswordService;
  let service: AdminAuthService;

  /** A stored admin row with a REAL bcrypt hash of [PASSWORD]. */
  async function adminRow(overrides: Record<string, unknown> = {}) {
    return {
      id: 'a1',
      username: 'superadmin',
      passwordHash: await passwords.hash(PASSWORD),
      role: AdminRole.SUPER_ADMIN,
      active: true,
      createdAt: new Date('2026-07-29T00:00:00Z'),
      createdBy: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    prisma = { adminUser: { findUnique: jest.fn() } };
    jwt = { signAsync: jest.fn().mockResolvedValue('signed.jwt.token') };
    throttle = {
      assertNotLockedOut: jest.fn().mockResolvedValue(undefined),
      recordFailure: jest.fn().mockResolvedValue(undefined),
      clear: jest.fn().mockResolvedValue(undefined),
    };
    passwords = new PasswordService();
    service = new AdminAuthService(
      prisma as unknown as PrismaService,
      jwt as unknown as JwtService,
      passwords,
      throttle as unknown as LoginThrottleService,
    );
  });

  it('issues an admin-kind JWT on correct credentials and clears the throttle', async () => {
    prisma.adminUser.findUnique.mockResolvedValue(await adminRow());

    const result = await service.login('superadmin', PASSWORD, IP);

    expect(result.accessToken).toBe('signed.jwt.token');
    expect(jwt.signAsync).toHaveBeenCalledWith({
      sub: 'a1',
      username: 'superadmin',
      kind: ADMIN_TOKEN_KIND,
      adminRole: AdminRole.SUPER_ADMIN,
    });
    // A successful login wipes the failure counter, so four fumbles followed by
    // the right password leave the admin with a clean slate.
    expect(throttle.clear).toHaveBeenCalledWith('superadmin', IP);
    expect(throttle.recordFailure).not.toHaveBeenCalled();
  });

  it('never returns the password hash', async () => {
    prisma.adminUser.findUnique.mockResolvedValue(await adminRow());

    const result = await service.login('superadmin', PASSWORD, IP);

    expect(result.admin).not.toHaveProperty('passwordHash');
    expect(JSON.stringify(result)).not.toContain('$2');
  });

  it('is case-insensitive on the username', async () => {
    prisma.adminUser.findUnique.mockResolvedValue(await adminRow());

    await service.login('  SuperAdmin  ', PASSWORD, IP);

    expect(prisma.adminUser.findUnique).toHaveBeenCalledWith({
      where: { username: 'superadmin' },
    });
  });

  it('rejects a wrong password with the generic message', async () => {
    prisma.adminUser.findUnique.mockResolvedValue(await adminRow());

    await expect(service.login('superadmin', 'wrong-password', IP)).rejects.toThrow(
      UnauthorizedException,
    );
    expect(throttle.recordFailure).toHaveBeenCalledWith('superadmin', IP);
  });

  it('gives an unknown username the SAME error as a wrong password', async () => {
    // The whole point: a caller must not be able to tell "no such admin" from
    // "wrong password", or they can enumerate valid usernames for free.
    prisma.adminUser.findUnique.mockResolvedValue(await adminRow());
    const wrongPassword = await service
      .login('superadmin', 'wrong-password', IP)
      .catch((e: Error) => e.message);

    prisma.adminUser.findUnique.mockResolvedValue(null);
    const unknownUser = await service
      .login('ghost', 'wrong-password', IP)
      .catch((e: Error) => e.message);

    expect(unknownUser).toBe(wrongPassword);
    expect(unknownUser).toBe('اسم المستخدم أو كلمة المرور غير صحيحة.');
  });

  it('gives a DISABLED account the same error too, even with the right password', async () => {
    prisma.adminUser.findUnique.mockResolvedValue(await adminRow({ active: false }));

    await expect(service.login('superadmin', PASSWORD, IP)).rejects.toThrow(
      'اسم المستخدم أو كلمة المرور غير صحيحة.',
    );
    expect(jwt.signAsync).not.toHaveBeenCalled();
  });

  it('still burns a bcrypt comparison when the username does not exist', async () => {
    // Guards the timing side-channel: an instant 401 for unknown usernames vs a
    // ~250ms one for real accounts is itself a username oracle.
    prisma.adminUser.findUnique.mockResolvedValue(null);
    const spy = jest.spyOn(passwords, 'verifyDecoy');

    await expect(service.login('ghost', 'whatever', IP)).rejects.toThrow(UnauthorizedException);

    expect(spy).toHaveBeenCalledWith('whatever');
  });

  it('refuses to touch the database once the throttle has locked out', async () => {
    throttle.assertNotLockedOut.mockRejectedValue(new HttpException('too many', 429));

    await expect(service.login('superadmin', PASSWORD, IP)).rejects.toThrow(HttpException);

    expect(prisma.adminUser.findUnique).not.toHaveBeenCalled();
  });
});
