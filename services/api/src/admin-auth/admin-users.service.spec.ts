import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { AdminRole } from '@prisma/client';
import { AdminUsersService } from './admin-users.service';
import { PasswordService } from './password.service';
import { PrismaService } from '../prisma/prisma.service';

const SUPER = 'super-1';

describe('AdminUsersService', () => {
  let prisma: {
    adminUser: {
      findMany: jest.Mock;
      findUnique: jest.Mock;
      create: jest.Mock;
      update: jest.Mock;
    };
  };
  let service: AdminUsersService;

  const row = (o: Record<string, unknown> = {}) => ({
    id: 'a2',
    username: 'zainab',
    passwordHash: '$2b$12$hash',
    role: AdminRole.ADMIN,
    active: true,
    createdAt: new Date('2026-07-29T00:00:00Z'),
    createdBy: SUPER,
    ...o,
  });

  beforeEach(() => {
    prisma = {
      adminUser: {
        findMany: jest.fn(),
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
    };
    service = new AdminUsersService(prisma as unknown as PrismaService, new PasswordService());
  });

  describe('list', () => {
    it('never leaks a password hash', async () => {
      prisma.adminUser.findMany.mockResolvedValue([row(), row({ id: 'a3', username: 'ali' })]);

      const listed = await service.list();

      expect(listed).toHaveLength(2);
      for (const admin of listed) {
        expect(admin).not.toHaveProperty('passwordHash');
      }
      expect(JSON.stringify(listed)).not.toContain('$2b$');
    });
  });

  describe('create', () => {
    it('stores a bcrypt hash — never the plaintext', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(null);
      prisma.adminUser.create.mockImplementation(async ({ data }: any) => row(data));

      await service.create({ username: 'Zainab', password: 'a-good-password' }, SUPER);

      const { data } = prisma.adminUser.create.mock.calls[0][0];
      expect(data.passwordHash).toMatch(/^\$2[aby]\$/);
      expect(data.passwordHash).not.toContain('a-good-password');
      // Lower-cased on the way in, so `Zainab` and `zainab` can't both exist.
      expect(data.username).toBe('zainab');
      expect(data.createdBy).toBe(SUPER);
    });

    it('always creates a plain ADMIN, never a second super admin', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(null);
      prisma.adminUser.create.mockImplementation(async ({ data }: any) => row(data));

      await service.create({ username: 'zainab', password: 'a-good-password' }, SUPER);

      expect(prisma.adminUser.create.mock.calls[0][0].data.role).toBe(AdminRole.ADMIN);
    });

    it('rejects a duplicate username', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(row());

      await expect(
        service.create({ username: 'zainab', password: 'a-good-password' }, SUPER),
      ).rejects.toThrow(ConflictException);
      expect(prisma.adminUser.create).not.toHaveBeenCalled();
    });

    it('rejects a weak password before writing anything', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(null);

      await expect(service.create({ username: 'zainab', password: 'short' }, SUPER)).rejects.toThrow(
        BadRequestException,
      );
      expect(prisma.adminUser.create).not.toHaveBeenCalled();
    });
  });

  describe('setActive', () => {
    it('disables a normal admin', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(row());
      prisma.adminUser.update.mockResolvedValue(row({ active: false }));

      const updated = await service.setActive('a2', false, SUPER);

      expect(prisma.adminUser.update).toHaveBeenCalledWith({
        where: { id: 'a2' },
        data: { active: false },
      });
      expect(updated.active).toBe(false);
    });

    it('refuses to let the super admin disable themselves', async () => {
      // Otherwise one click removes the only account that can create admins,
      // and the only way back is a database console.
      prisma.adminUser.findUnique.mockResolvedValue(
        row({ id: SUPER, role: AdminRole.SUPER_ADMIN }),
      );

      await expect(service.setActive(SUPER, false, SUPER)).rejects.toThrow(BadRequestException);
      expect(prisma.adminUser.update).not.toHaveBeenCalled();
    });

    it('refuses to disable the super admin at all', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(
        row({ id: SUPER, role: AdminRole.SUPER_ADMIN }),
      );

      await expect(service.setActive(SUPER, false, 'someone-else')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('404s on an unknown admin', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(null);

      await expect(service.setActive('nope', false, SUPER)).rejects.toThrow(NotFoundException);
    });
  });

  describe('resetPassword', () => {
    it('writes a fresh hash and returns no hash', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(row());
      prisma.adminUser.update.mockImplementation(async ({ data }: any) => row(data));

      const result = await service.resetPassword('a2', 'brand-new-password');

      const { data } = prisma.adminUser.update.mock.calls[0][0];
      expect(data.passwordHash).toMatch(/^\$2[aby]\$/);
      expect(data.passwordHash).not.toContain('brand-new-password');
      expect(result).not.toHaveProperty('passwordHash');
    });

    it('enforces the password policy', async () => {
      prisma.adminUser.findUnique.mockResolvedValue(row());

      await expect(service.resetPassword('a2', 'weak')).rejects.toThrow(BadRequestException);
      expect(prisma.adminUser.update).not.toHaveBeenCalled();
    });
  });
});
