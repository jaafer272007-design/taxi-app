import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CorridorService } from './corridor.service';

type PrismaMock = {
  corridor: {
    findFirst: jest.Mock;
    findUnique: jest.Mock;
    create: jest.Mock;
    update: jest.Mock;
  };
};

describe('CorridorService', () => {
  let prisma: PrismaMock;
  let service: CorridorService;

  beforeEach(() => {
    prisma = {
      corridor: {
        findFirst: jest.fn().mockResolvedValue(null),
        findUnique: jest.fn(),
        create: jest.fn().mockImplementation(({ data }) => ({ id: 'c1', ...data })),
        update: jest.fn().mockImplementation(({ data }) => ({ id: 'c1', ...data })),
      },
    };
    service = new CorridorService(prisma as unknown as PrismaService);
  });

  describe('create', () => {
    it('creates a corridor for a valid, free city pair', async () => {
      const res = await service.create({
        originCity: 'Najaf',
        destCity: 'Baghdad',
        pricePerSeat: 6000,
      });
      expect(prisma.corridor.create).toHaveBeenCalled();
      expect(res.originCity).toBe('Najaf');
      expect(res.active).toBe(true);
    });

    it('rejects origin === dest (400) without creating', async () => {
      await expect(
        service.create({ originCity: 'Najaf', destCity: 'Najaf', pricePerSeat: 6000 }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('rejects a duplicate (origin,dest) pair (409) without creating', async () => {
      prisma.corridor.findFirst.mockResolvedValue({ id: 'existing' });
      await expect(
        service.create({ originCity: 'Najaf', destCity: 'Karbala', pricePerSeat: 6000 }),
      ).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('maps a P2002 race on create to a 409', async () => {
      prisma.corridor.create.mockRejectedValue({ code: 'P2002' });
      await expect(
        service.create({ originCity: 'Najaf', destCity: 'Baghdad', pricePerSeat: 6000 }),
      ).rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('update', () => {
    it('404s a missing corridor', async () => {
      prisma.corridor.findUnique.mockResolvedValue(null);
      await expect(service.update('nope', { pricePerSeat: 7000 })).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('updates price without re-checking the pair', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
      });
      await service.update('c1', { pricePerSeat: 7000 });
      expect(prisma.corridor.findFirst).not.toHaveBeenCalled(); // no pair change → no dup check
      expect(prisma.corridor.update).toHaveBeenCalled();
    });

    it('toggles active without a pair check', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
      });
      await service.update('c1', { active: false });
      expect(prisma.corridor.findFirst).not.toHaveBeenCalled();
      expect(prisma.corridor.update).toHaveBeenCalled();
    });

    it('rejects changing the pair to one owned by another corridor (409)', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
      });
      prisma.corridor.findFirst.mockResolvedValue({ id: 'other' });
      await expect(service.update('c1', { destCity: 'Baghdad' })).rejects.toBeInstanceOf(
        ConflictException,
      );
      expect(prisma.corridor.update).not.toHaveBeenCalled();
    });

    it('rejects changing the pair to origin === dest (400)', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
      });
      await expect(service.update('c1', { destCity: 'Najaf' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });
  });
});
