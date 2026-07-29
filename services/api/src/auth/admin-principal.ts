import { AdminRole, UserRole } from '@prisma/client';

/**
 * The contract between the two authentication paths. It lives in `auth/`
 * rather than `admin-auth/` on purpose: `JwtStrategy` (here) and
 * `AdminAuthService` (there) both need it, and putting it in either module
 * would make them import each other.
 */

/** Marks a JWT as belonging to an AdminUser rather than a User. */
export const ADMIN_TOKEN_KIND = 'admin';

export interface AdminJwtPayload {
  sub: string;
  username: string;
  kind: typeof ADMIN_TOKEN_KIND;
  adminRole: AdminRole;
}

/**
 * What `req.user` holds when an admin is authenticated.
 *
 * It deliberately carries `roles: [UserRole.ADMIN]`. Every existing
 * admin-guarded route (`corridors`, `admin/drivers`, `admin/dashboard`,
 * document access) already asks "does this principal have the ADMIN role?", so
 * shaping the admin this way makes all of them accept an admin JWT with no
 * change to any guard — and, just as importantly, without widening what a
 * *rider* JWT can reach.
 *
 * `adminRole` is the finer distinction (SUPER_ADMIN vs ADMIN) and is read only
 * by `SuperAdminGuard`.
 *
 * There is no `passwordHash` field here, and there never should be: this object
 * is attached to the request and is one careless `JSON.stringify(req.user)` away
 * from a log file.
 */
export interface AdminPrincipal {
  id: string;
  username: string;
  adminRole: AdminRole;
  roles: UserRole[];
  isAdminAccount: true;
}

/** Narrows `req.user` to an admin. False for rider/driver principals. */
export function isAdminPrincipal(principal: unknown): principal is AdminPrincipal {
  return (
    typeof principal === 'object' &&
    principal !== null &&
    (principal as AdminPrincipal).isAdminAccount === true
  );
}
