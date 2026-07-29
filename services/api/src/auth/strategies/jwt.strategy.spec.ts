import { UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AdminRole, UserRole } from '@prisma/client';
import { JwtStrategy } from './jwt.strategy';
import { PrismaService } from '../../prisma/prisma.service';
import { ADMIN_TOKEN_KIND, isAdminPrincipal } from '../admin-principal';

const config = { getOrThrow: () => 'test-secret' } as unknown as ConfigService;

describe('JwtStrategy (two principal kinds on one token format)', () => {
  let prisma: {
    user: { findUnique: jest.Mock };
    adminUser: { findUnique: jest.Mock };
  };
  let strategy: JwtStrategy;

  const adminRow = (o: Record<string, unknown> = {}) => ({
    id: 'a1',
    username: 'superadmin',
    passwordHash: '$2b$12$hash',
    role: AdminRole.SUPER_ADMIN,
    active: true,
    createdAt: new Date(),
    createdBy: null,
    ...o,
  });

  beforeEach(() => {
    prisma = {
      user: { findUnique: jest.fn() },
      adminUser: { findUnique: jest.fn() },
    };
    strategy = new JwtStrategy(config, prisma as unknown as PrismaService);
  });

  describe('rider / driver tokens', () => {
    it('resolves to the User row', async () => {
      const user = { id: 'u1', phone: '+9647700000000', roles: [UserRole.RIDER] };
      prisma.user.findUnique.mockResolvedValue(user);

      const principal = await strategy.validate({
        sub: 'u1',
        phone: '+9647700000000',
        roles: ['RIDER'],
      });

      expect(principal).toBe(user);
      expect(isAdminPrincipal(principal)).toBe(false);
      expect(prisma.adminUser.findUnique).not.toHaveBeenCalled();
    });

    it('401s when the user is gone', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(
        strategy.validate({ sub: 'u1', phone: '+964', roles: [] }),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  describe('admin tokens', () => {
    const adminPayload = {
      sub: 'a1',
      username: 'superadmin',
      kind: ADMIN_TOKEN_KIND as typeof ADMIN_TOKEN_KIND,
      adminRole: AdminRole.SUPER_ADMIN,
    };

    it('resolves to an admin principal carrying the ADMIN role', async () => {
      // Carrying `roles: [ADMIN]` is what makes every existing admin-guarded
      // endpoint (corridors, driver approval, dashboard) accept an admin JWT
      // without touching RolesGuard.
      prisma.adminUser.findUnique.mockResolvedValue(adminRow());

      const principal = await strategy.validate(adminPayload);

      expect(isAdminPrincipal(principal)).toBe(true);
      expect(principal).toMatchObject({
        id: 'a1',
        username: 'superadmin',
        adminRole: AdminRole.SUPER_ADMIN,
        roles: [UserRole.ADMIN],
        isAdminAccount: true,
      });
      expect(prisma.user.findUnique).not.toHaveBeenCalled();
    });

    it('never exposes the password hash on the request principal', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(adminRow());

      const principal = await strategy.validate(adminPayload);

      expect(principal).not.toHaveProperty('passwordHash');
      expect(JSON.stringify(principal)).not.toContain('$2b$');
    });

    it('401s a DISABLED admin, so revocation is immediate', async () => {
      // The JWT is still cryptographically valid; the DB re-read is what makes
      // "disable this admin" take effect on the very next request.
      prisma.adminUser.findUnique.mockResolvedValue(adminRow({ active: false }));

      await expect(strategy.validate(adminPayload)).rejects.toThrow(UnauthorizedException);
    });

    it('401s an admin whose row was deleted', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(null);

      await expect(strategy.validate(adminPayload)).rejects.toThrow(UnauthorizedException);
    });

    it('takes the role from the ROW, not from the token', async () => {
      // A demoted super admin holding an old token must not stay super.
      prisma.adminUser.findUnique.mockResolvedValue(adminRow({ role: AdminRole.ADMIN }));

      const principal = await strategy.validate(adminPayload);

      expect((principal as { adminRole: AdminRole }).adminRole).toBe(AdminRole.ADMIN);
    });
  });
});
