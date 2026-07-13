import { ConfigService } from '@nestjs/config';
import { NotificationService } from './notification.service';
import { PrismaService } from '../prisma/prisma.service';

// Avoid touching the real Firebase SDK (no credential parsing / network).
jest.mock('firebase-admin', () => ({
  apps: [],
  credential: { cert: jest.fn(() => ({})) },
  initializeApp: jest.fn(),
  messaging: jest.fn(),
}));

function makeConfig(vals: Record<string, string | undefined>): ConfigService {
  return { get: (k: string) => vals[k] } as unknown as ConfigService;
}

const FCM_ENV = {
  FIREBASE_PROJECT_ID: 'p',
  FIREBASE_CLIENT_EMAIL: 'e',
  FIREBASE_PRIVATE_KEY: 'k',
};

describe('NotificationService.send', () => {
  it('no-ops when the user has no devices', async () => {
    const prisma = {
      deviceToken: { findMany: jest.fn().mockResolvedValue([]), deleteMany: jest.fn() },
    };
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));
    const deliver = jest.spyOn(svc as any, 'deliverToTokens');

    await svc.send('u1', { title: 't', body: 'b' });

    expect(deliver).not.toHaveBeenCalled();
    expect(prisma.deviceToken.deleteMany).not.toHaveBeenCalled();
  });

  it('DEV-ONLY fallback: logs and does not deliver when FCM is unconfigured', async () => {
    const prisma = {
      deviceToken: { findMany: jest.fn().mockResolvedValue([{ token: 'a' }]), deleteMany: jest.fn() },
    };
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));
    const deliver = jest.spyOn(svc as any, 'deliverToTokens');

    await svc.send('u1', { title: 't', body: 'b' });

    expect(deliver).not.toHaveBeenCalled();
    expect(prisma.deviceToken.deleteMany).not.toHaveBeenCalled();
  });

  it('prunes invalid tokens returned by delivery when FCM is configured', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([{ token: 'good' }, { token: 'bad' }]),
        deleteMany: jest.fn(),
      },
    };
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    jest.spyOn(svc as any, 'deliverToTokens').mockResolvedValue(['bad']);

    await svc.send('u1', { title: 't', body: 'b' });

    expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({ where: { token: { in: ['bad'] } } });
  });

  it('never throws even if delivery fails', async () => {
    const prisma = {
      deviceToken: { findMany: jest.fn().mockResolvedValue([{ token: 'x' }]), deleteMany: jest.fn() },
    };
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    jest.spyOn(svc as any, 'deliverToTokens').mockRejectedValue(new Error('fcm down'));

    await expect(svc.send('u1', { title: 't', body: 'b' })).resolves.toBeUndefined();
  });
});
