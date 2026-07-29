import { ForbiddenException } from '@nestjs/common';
import { AdminRole, UserRole } from '@prisma/client';
import { SuperAdminGuard } from './super-admin.guard';
import type { AdminPrincipal } from '../../auth/admin-principal';

function contextWith(user: unknown) {
  return { switchToHttp: () => ({ getRequest: () => ({ user }) }) } as any;
}

function admin(role: AdminRole): AdminPrincipal {
  return {
    id: 'a1',
    username: role === AdminRole.SUPER_ADMIN ? 'superadmin' : 'zainab',
    adminRole: role,
    roles: [UserRole.ADMIN],
    isAdminAccount: true,
  };
}

describe('SuperAdminGuard', () => {
  const guard = new SuperAdminGuard();

  it('allows the super admin', () => {
    expect(guard.canActivate(contextWith(admin(AdminRole.SUPER_ADMIN)))).toBe(true);
  });

  it('BLOCKS a normal admin — this is the whole role separation', () => {
    expect(() => guard.canActivate(contextWith(admin(AdminRole.ADMIN)))).toThrow(
      ForbiddenException,
    );
  });

  it('blocks a rider/driver principal even if it claims the ADMIN role', () => {
    // A `User` row with ADMIN in `roles` passes RolesGuard on the operational
    // endpoints, but it is not an admin ACCOUNT and must not manage admins.
    expect(() =>
      guard.canActivate(contextWith({ id: 'u1', phone: '+9647700000000', roles: [UserRole.ADMIN] })),
    ).toThrow(ForbiddenException);
  });

  it('blocks an unauthenticated request', () => {
    expect(() => guard.canActivate(contextWith(undefined))).toThrow(ForbiddenException);
  });

  it('cannot be fooled by a hand-crafted object claiming to be an admin session', () => {
    // `isAdminAccount` is set only by JwtStrategy after a DB lookup, so this
    // only proves the narrowing is on the flag AND the role together.
    expect(() =>
      guard.canActivate(contextWith({ isAdminAccount: true, adminRole: 'ADMIN' })),
    ).toThrow(ForbiddenException);
  });
});
