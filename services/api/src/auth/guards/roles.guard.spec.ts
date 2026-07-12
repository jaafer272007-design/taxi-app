import { ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { RolesGuard } from './roles.guard';

function contextWith(user: unknown) {
  return {
    getHandler: () => ({}),
    getClass: () => ({}),
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as any;
}

function guardRequiring(required?: UserRole[]) {
  const reflector = { getAllAndOverride: jest.fn().mockReturnValue(required) } as unknown as Reflector;
  return new RolesGuard(reflector);
}

describe('RolesGuard', () => {
  it('allows the route when no roles are required', () => {
    expect(guardRequiring(undefined).canActivate(contextWith({ roles: [] }))).toBe(true);
  });

  it('allows an ADMIN on an ADMIN-only route', () => {
    const ctx = contextWith({ roles: [UserRole.ADMIN] });
    expect(guardRequiring([UserRole.ADMIN]).canActivate(ctx)).toBe(true);
  });

  it('allows a user who has ADMIN among several roles', () => {
    const ctx = contextWith({ roles: [UserRole.RIDER, UserRole.DRIVER, UserRole.ADMIN] });
    expect(guardRequiring([UserRole.ADMIN]).canActivate(ctx)).toBe(true);
  });

  it('forbids a non-admin (RIDER) on an ADMIN-only route', () => {
    const ctx = contextWith({ roles: [UserRole.RIDER] });
    expect(() => guardRequiring([UserRole.ADMIN]).canActivate(ctx)).toThrow(ForbiddenException);
  });

  it('forbids when the request has no authenticated user', () => {
    expect(() => guardRequiring([UserRole.ADMIN]).canActivate(contextWith(undefined))).toThrow(
      ForbiddenException,
    );
  });
});
