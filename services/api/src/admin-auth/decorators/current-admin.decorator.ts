import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AdminPrincipal, isAdminPrincipal } from '../../auth/admin-principal';

/**
 * Injects the authenticated admin. Returns null when the request was made with
 * a rider/driver token, so a handler can never silently treat a passenger as an
 * admin — routes that need one are behind `SuperAdminGuard` or `RolesGuard`.
 */
export const CurrentAdmin = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AdminPrincipal | null => {
    const principal = ctx.switchToHttp().getRequest().user;
    return isAdminPrincipal(principal) ? principal : null;
  },
);
