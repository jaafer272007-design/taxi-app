import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AdminRole, AdminUser } from '@prisma/client';
import { ADMIN_TOKEN_KIND, AdminJwtPayload } from '../auth/admin-principal';
import { PrismaService } from '../prisma/prisma.service';
import { LoginThrottleService } from './login-throttle.service';
import { PasswordService } from './password.service';

/** The admin as the API is allowed to describe it. Never carries the hash. */
export interface AdminSummary {
  id: string;
  username: string;
  role: AdminRole;
  active: boolean;
  createdAt: Date;
  createdBy: string | null;
}

export function toAdminSummary(admin: AdminUser): AdminSummary {
  return {
    id: admin.id,
    username: admin.username,
    role: admin.role,
    active: admin.active,
    createdAt: admin.createdAt,
    createdBy: admin.createdBy,
  };
}

/**
 * Username + password login for admins.
 *
 * ## Why every failure returns the same sentence
 *
 * "No such user", "wrong password" and "account disabled" are all reported as
 * `اسم المستخدم أو كلمة المرور غير صحيحة.` An attacker who can tell those apart
 * gets a free username oracle: they can enumerate valid accounts without ever
 * guessing a password, which turns one hard problem into two easy ones. The
 * timing is equalised too — see `PasswordService.verifyDecoy`.
 */
@Injectable()
export class AdminAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly passwords: PasswordService,
    private readonly throttle: LoginThrottleService,
  ) {}

  /** The single message every login failure returns, whatever went wrong. */
  private static readonly GENERIC_FAILURE = 'اسم المستخدم أو كلمة المرور غير صحيحة.';

  async login(
    username: string,
    password: string,
    ip: string,
  ): Promise<{ accessToken: string; admin: AdminSummary }> {
    const normalized = username.trim().toLowerCase();

    // Checked BEFORE touching the database, so a locked-out attacker cannot
    // keep probing for usernames through response timing.
    await this.throttle.assertNotLockedOut(normalized, ip);

    const admin = await this.prisma.adminUser.findUnique({ where: { username: normalized } });

    // Unknown username: still run a bcrypt comparison so this branch costs the
    // same as a real one, then fail identically.
    if (!admin) {
      await this.passwords.verifyDecoy(password);
      await this.throttle.recordFailure(normalized, ip);
      throw new UnauthorizedException(AdminAuthService.GENERIC_FAILURE);
    }

    const ok = await this.passwords.verify(password, admin.passwordHash);

    // A disabled account is treated exactly like a wrong password — telling the
    // caller "this account exists but is disabled" is the same leak.
    if (!ok || !admin.active) {
      await this.throttle.recordFailure(normalized, ip);
      throw new UnauthorizedException(AdminAuthService.GENERIC_FAILURE);
    }

    await this.throttle.clear(normalized, ip);

    const payload: AdminJwtPayload = {
      sub: admin.id,
      username: admin.username,
      kind: ADMIN_TOKEN_KIND,
      adminRole: admin.role,
    };

    return {
      accessToken: await this.jwt.signAsync(payload),
      admin: toAdminSummary(admin),
    };
  }
}
