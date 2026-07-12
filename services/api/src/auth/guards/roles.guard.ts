import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { ROLES_KEY } from '../decorators/roles.decorator';

/**
 * Reads the required roles set by @Roles(...) and compares them against the
 * authenticated user's roles (populated by JwtStrategy.validate from the DB).
 * Must run AFTER JwtAuthGuard: `@UseGuards(JwtAuthGuard, RolesGuard)`.
 */
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    // No @Roles on the route → no role restriction.
    if (!required || required.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const roles: UserRole[] = request.user?.roles ?? [];

    const allowed = required.some((role) => roles.includes(role));
    if (!allowed) {
      throw new ForbiddenException('ليس لديك صلاحية للوصول لهذه العملية.');
    }
    return true;
  }
}
