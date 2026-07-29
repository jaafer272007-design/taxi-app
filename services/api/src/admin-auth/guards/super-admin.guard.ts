import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { AdminRole } from '@prisma/client';
import { isAdminPrincipal } from '../../auth/admin-principal';

/**
 * Restricts a route to the single SUPER_ADMIN account.
 *
 * This is the ONLY privilege that separates the two admin roles: managing admin
 * accounts. Everything else — corridors, pricing, driver approval, the
 * dashboard — is open to both and is guarded by `RolesGuard` instead.
 *
 * Must run after `JwtAuthGuard`: `@UseGuards(JwtAuthGuard, SuperAdminGuard)`.
 *
 * A rider or driver JWT fails here too, not just a normal admin's: the
 * `isAdminPrincipal` check rejects anything that did not come from the admin
 * login, so this guard alone is sufficient on these routes.
 */
@Injectable()
export class SuperAdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const principal = context.switchToHttp().getRequest().user;

    if (!isAdminPrincipal(principal) || principal.adminRole !== AdminRole.SUPER_ADMIN) {
      throw new ForbiddenException('هذه العملية مخصّصة للمدير الأعلى فقط.');
    }
    return true;
  }
}
