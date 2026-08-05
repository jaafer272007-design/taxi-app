import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NotificationType } from '@prisma/client';
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

const EVENT = {
  type: NotificationType.TRIP_CANCELLED,
  title: 'أُلغيت الرحلة',
  body: 'ألغى السائق هذه الرحلة.',
  tripId: 't1',
};

/** A Prisma double with BOTH sinks wired. */
function makePrisma(devices: Array<{ token: string }> = []) {
  return {
    deviceToken: {
      findMany: jest.fn().mockResolvedValue(devices),
      deleteMany: jest.fn(),
    },
    notification: {
      create: jest.fn().mockResolvedValue({ id: 'n1' }),
      findMany: jest.fn(),
      findUnique: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      count: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
  };
}

describe('NotificationService.send — one emitter, two sinks', () => {
  it('STORES the notification even when the user has no device at all', async () => {
    // The case that mattered most. Push is blocked on Firebase credentials and
    // nobody has a registered device, so the old early-return meant the user
    // was told nothing at all — a driver could cancel a trip and the rider
    // would find out by turning up at the pickup point.
    const prisma = makePrisma([]);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));
    const deliver = jest.spyOn(svc as never, 'deliverToTokens' as never);

    await svc.send('u1', EVENT);

    expect(prisma.notification.create).toHaveBeenCalledWith({
      data: {
        userId: 'u1',
        type: NotificationType.TRIP_CANCELLED,
        title: EVENT.title,
        body: EVENT.body,
        tripId: 't1',
        bookingId: null,
      },
    });
    expect(deliver).not.toHaveBeenCalled();
  });

  it('one event writes BOTH sinks: a stored row and a push attempt', async () => {
    const prisma = makePrisma([{ token: 'good' }]);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    const deliver = jest
      .spyOn(svc as never, 'deliverToTokens' as never)
      .mockResolvedValue([] as never);

    await svc.send('u1', EVENT);

    expect(prisma.notification.create).toHaveBeenCalledTimes(1);
    expect(deliver).toHaveBeenCalledTimes(1);
    // …and with the SAME event: the two sinks cannot describe it differently,
    // which is the entire reason `type` is a field on the payload rather than
    // a string each call site writes into a data map by hand.
    expect(deliver.mock.calls[0][1]).toMatchObject({
      type: NotificationType.TRIP_CANCELLED,
    });
  });

  it('still stores when the push throws — the centre is not hostage to FCM', async () => {
    const prisma = makePrisma([{ token: 'x' }]);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    jest
      .spyOn(svc as never, 'deliverToTokens' as never)
      .mockRejectedValue(new Error('fcm down') as never);

    await expect(svc.send('u1', EVENT)).resolves.toBeUndefined();

    expect(prisma.notification.create).toHaveBeenCalledTimes(1);
  });

  it('still pushes when the STORE throws — neither sink blocks the other', async () => {
    const prisma = makePrisma([{ token: 'x' }]);
    prisma.notification.create.mockRejectedValue(new Error('db down'));
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    const deliver = jest
      .spyOn(svc as never, 'deliverToTokens' as never)
      .mockResolvedValue([] as never);

    await expect(svc.send('u1', EVENT)).resolves.toBeUndefined();

    expect(deliver).toHaveBeenCalledTimes(1);
  });

  it('DEV-ONLY fallback: logs and does not deliver when FCM is unconfigured', async () => {
    const prisma = makePrisma([{ token: 'a' }]);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));
    const deliver = jest.spyOn(svc as never, 'deliverToTokens' as never);

    await svc.send('u1', EVENT);

    expect(deliver).not.toHaveBeenCalled();
    expect(prisma.deviceToken.deleteMany).not.toHaveBeenCalled();
    // …but the in-app sink still fired, which is the whole point of this work.
    expect(prisma.notification.create).toHaveBeenCalledTimes(1);
  });

  it('prunes invalid tokens returned by delivery when FCM is configured', async () => {
    const prisma = makePrisma([{ token: 'good' }, { token: 'bad' }]);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    jest
      .spyOn(svc as never, 'deliverToTokens' as never)
      .mockResolvedValue(['bad'] as never);

    await svc.send('u1', EVENT);

    expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({
      where: { token: { in: ['bad'] } },
    });
  });

  it('never throws even if delivery fails', async () => {
    const prisma = makePrisma([{ token: 'x' }]);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig(FCM_ENV));
    jest
      .spyOn(svc as never, 'deliverToTokens' as never)
      .mockRejectedValue(new Error('fcm down') as never);

    await expect(svc.send('u1', EVENT)).resolves.toBeUndefined();
  });
});

describe('NotificationService — the centre', () => {
  it('returns the list and the unread count together', async () => {
    // One round trip, and no window in which the badge disagrees with the list.
    const prisma = makePrisma();
    prisma.notification.findMany.mockResolvedValue([{ id: 'n1' }, { id: 'n2' }]);
    prisma.notification.count.mockResolvedValue(1);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));

    const res = await svc.list('u1');

    expect(res).toEqual({ unreadCount: 1, notifications: [{ id: 'n1' }, { id: 'n2' }] });
    expect(prisma.notification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId: 'u1' },
        orderBy: { createdAt: 'desc' },
      }),
    );
  });

  it('counts only UNREAD rows for the badge', async () => {
    const prisma = makePrisma();
    prisma.notification.count.mockResolvedValue(3);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));

    await expect(svc.unreadCount('u1')).resolves.toEqual({ unreadCount: 3 });
    expect(prisma.notification.count).toHaveBeenCalledWith({
      where: { userId: 'u1', readAt: null },
    });
  });

  it('marking read is idempotent — a second read does not move the timestamp', async () => {
    const already = new Date('2026-01-01T00:00:00Z');
    const prisma = makePrisma();
    prisma.notification.findUnique.mockResolvedValue({ userId: 'u1', readAt: already });
    prisma.notification.findUniqueOrThrow.mockResolvedValue({ id: 'n1', readAt: already });
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));

    await svc.markRead('u1', 'n1');

    expect(prisma.notification.update).not.toHaveBeenCalled();
  });

  it('403s when the notification belongs to someone else', async () => {
    const prisma = makePrisma();
    prisma.notification.findUnique.mockResolvedValue({ userId: 'someone-else', readAt: null });
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));

    await expect(svc.markRead('u1', 'n1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.notification.update).not.toHaveBeenCalled();
  });

  it('404s an unknown notification', async () => {
    const prisma = makePrisma();
    prisma.notification.findUnique.mockResolvedValue(null);
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));

    await expect(svc.markRead('u1', 'nope')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('mark-all-read touches only this user, and only the unread', async () => {
    const prisma = makePrisma();
    prisma.notification.updateMany.mockResolvedValue({ count: 4 });
    const svc = new NotificationService(prisma as unknown as PrismaService, makeConfig({}));

    await expect(svc.markAllRead('u1')).resolves.toEqual({ updated: 4 });
    expect(prisma.notification.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: 'u1', readAt: null } }),
    );
  });
});
