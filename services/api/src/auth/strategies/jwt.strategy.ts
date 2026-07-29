import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { User, UserRole } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { ADMIN_TOKEN_KIND, AdminJwtPayload, AdminPrincipal } from '../admin-principal';

export interface JwtPayload {
  sub: string;
  phone: string;
  roles: string[];
}

/**
 * One JWT strategy, two kinds of principal.
 *
 * Riders and drivers authenticate with phone + WhatsApp OTP and live in
 * `User`. Admins authenticate with username + password and live in
 * `AdminUser`. Their tokens are told apart by the `kind` claim, which only the
 * admin login issues — a rider token has no `kind`, so it can never be mistaken
 * for an admin one even if the two tables ever collide on an id.
 *
 * Both principals are re-read from the database on every request rather than
 * trusted from the token body. That is what makes "disable this admin" take
 * effect immediately: their existing JWT stays cryptographically valid, but the
 * lookup below refuses it on the very next call.
 */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.getOrThrow<string>('JWT_SECRET'),
    });
  }

  /** Whatever this returns becomes `req.user`. */
  async validate(payload: JwtPayload | AdminJwtPayload): Promise<User | AdminPrincipal> {
    if ((payload as AdminJwtPayload).kind === ADMIN_TOKEN_KIND) {
      return this.validateAdmin(payload as AdminJwtPayload);
    }

    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) {
      throw new UnauthorizedException();
    }
    return user;
  }

  private async validateAdmin(payload: AdminJwtPayload): Promise<AdminPrincipal> {
    const admin = await this.prisma.adminUser.findUnique({ where: { id: payload.sub } });

    // Deleted or disabled since the token was issued → reject now rather than
    // waiting for the token to expire.
    if (!admin || !admin.active) {
      throw new UnauthorizedException();
    }

    // The role comes from the ROW, not from the token: demoting an admin must
    // take effect without waiting for their JWT to expire.
    return {
      id: admin.id,
      username: admin.username,
      adminRole: admin.role,
      roles: [UserRole.ADMIN],
      isAdminAccount: true,
    };
  }
}
