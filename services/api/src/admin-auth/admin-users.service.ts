import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { AdminRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AdminSummary, toAdminSummary } from './admin-auth.service';
import { PasswordService } from './password.service';

/**
 * Admin account management — SUPER_ADMIN only (enforced by `SuperAdminGuard` on
 * the controller).
 *
 * Every method here returns `AdminSummary`, which has no `passwordHash` field.
 * That is the mechanism, not a convention: there is no code path from this
 * service to an HTTP response that carries a hash, because the only shape it
 * can return doesn't have one.
 */
@Injectable()
export class AdminUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly passwords: PasswordService,
  ) {}

  /** Usernames are stored lower-cased so `Ali` and `ali` cannot both exist. */
  static normalizeUsername(username: string): string {
    return username.trim().toLowerCase();
  }

  async list(): Promise<AdminSummary[]> {
    const admins = await this.prisma.adminUser.findMany({
      orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
    });
    return admins.map(toAdminSummary);
  }

  async create(
    input: { username: string; password: string },
    createdBy: string,
  ): Promise<AdminSummary> {
    const username = AdminUsersService.normalizeUsername(input.username);
    if (username.length < 3) {
      throw new BadRequestException('اسم المستخدم يجب أن يكون 3 أحرف على الأقل.');
    }
    this.passwords.assertStrongEnough(input.password);

    const existing = await this.prisma.adminUser.findUnique({ where: { username } });
    if (existing) {
      throw new ConflictException('اسم المستخدم مستخدم بالفعل.');
    }

    const admin = await this.prisma.adminUser.create({
      data: {
        username,
        passwordHash: await this.passwords.hash(input.password),
        // Created admins are always plain ADMINs. There is exactly one super
        // admin and it comes from the environment — no endpoint can mint
        // another, so a compromised super-admin session cannot quietly
        // manufacture a second one to persist with.
        role: AdminRole.ADMIN,
        active: true,
        createdBy,
      },
    });
    return toAdminSummary(admin);
  }

  async setActive(id: string, active: boolean, actingAdminId: string): Promise<AdminSummary> {
    const target = await this.requireAdmin(id);

    // Locking the last way in is not a state anyone recovers from through the
    // UI, so both self-lockout and super-admin lockout are refused here.
    if (target.id === actingAdminId && !active) {
      throw new BadRequestException('لا يمكنك تعطيل حسابك أنت.');
    }
    if (target.role === AdminRole.SUPER_ADMIN && !active) {
      throw new BadRequestException('لا يمكن تعطيل حساب المدير الأعلى.');
    }

    const updated = await this.prisma.adminUser.update({ where: { id }, data: { active } });
    return toAdminSummary(updated);
  }

  async resetPassword(id: string, password: string): Promise<AdminSummary> {
    await this.requireAdmin(id);
    this.passwords.assertStrongEnough(password);

    const updated = await this.prisma.adminUser.update({
      where: { id },
      data: { passwordHash: await this.passwords.hash(password) },
    });
    return toAdminSummary(updated);
  }

  private async requireAdmin(id: string) {
    const admin = await this.prisma.adminUser.findUnique({ where: { id } });
    if (!admin) {
      throw new NotFoundException('حساب المدير غير موجود.');
    }
    return admin;
  }
}
