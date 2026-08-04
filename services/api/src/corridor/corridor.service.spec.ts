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

/** A valid price band (min <= suggested <= max) for tests not about pricing. */
const BAND = {
  suggestedPricePerSeat: 6000,
  minPricePerSeat: 3000,
  maxPricePerSeat: 12000,
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
        ...BAND,
      });
      expect(prisma.corridor.create).toHaveBeenCalled();
      expect(res.originCity).toBe('Najaf');
      expect(res.active).toBe(true);
    });

    it('rejects origin === dest (400) without creating', async () => {
      await expect(
        service.create({ originCity: 'Najaf', destCity: 'Najaf', ...BAND }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('rejects a duplicate (origin,dest) pair (409) without creating', async () => {
      prisma.corridor.findFirst.mockResolvedValue({ id: 'existing' });
      await expect(
        service.create({ originCity: 'Najaf', destCity: 'Karbala', ...BAND }),
      ).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('maps a P2002 race on create to a 409', async () => {
      prisma.corridor.create.mockRejectedValue({ code: 'P2002' });
      await expect(
        service.create({ originCity: 'Najaf', destCity: 'Baghdad', ...BAND }),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('persists all three prices', async () => {
      await service.create({ originCity: 'Najaf', destCity: 'Baghdad', ...BAND });

      expect(prisma.corridor.create.mock.calls[0][0].data).toMatchObject({
        suggestedPricePerSeat: 6000,
        minPricePerSeat: 3000,
        maxPricePerSeat: 12000,
      });
    });

    it('rejects min > max (400) without creating', async () => {
      await expect(
        service.create({
          originCity: 'Najaf',
          destCity: 'Baghdad',
          suggestedPricePerSeat: 6000,
          minPricePerSeat: 12000,
          maxPricePerSeat: 3000,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('rejects a suggestion below min (400)', async () => {
      // The suggestion is what the driver's form prefills. A suggestion outside
      // the band would prefill a value the very next POST /trips rejects.
      await expect(
        service.create({
          originCity: 'Najaf',
          destCity: 'Baghdad',
          suggestedPricePerSeat: 2000,
          minPricePerSeat: 3000,
          maxPricePerSeat: 12000,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('rejects a suggestion above max (400)', async () => {
      await expect(
        service.create({
          originCity: 'Najaf',
          destCity: 'Baghdad',
          suggestedPricePerSeat: 20000,
          minPricePerSeat: 3000,
          maxPricePerSeat: 12000,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.corridor.create).not.toHaveBeenCalled();
    });

    it('accepts a degenerate band where all three are equal', async () => {
      // A corridor the admin wants at ONE fixed price is expressible: min ==
      // suggested == max. The rule is `<=`, not `<`.
      await expect(
        service.create({
          originCity: 'Najaf',
          destCity: 'Baghdad',
          suggestedPricePerSeat: 6000,
          minPricePerSeat: 6000,
          maxPricePerSeat: 6000,
        }),
      ).resolves.toBeDefined();
    });
  });

  describe('update', () => {
    it('404s a missing corridor', async () => {
      prisma.corridor.findUnique.mockResolvedValue(null);
      await expect(service.update('nope', { suggestedPricePerSeat: 7000 })).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('updates price without re-checking the pair', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
        ...BAND,
      });
      await service.update('c1', { suggestedPricePerSeat: 7000 });
      expect(prisma.corridor.findFirst).not.toHaveBeenCalled(); // no pair change → no dup check
      expect(prisma.corridor.update).toHaveBeenCalled();
    });

    it('toggles active without a pair check', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
        ...BAND,
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
        ...BAND,
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
        ...BAND,
      });
      await expect(service.update('c1', { destCity: 'Najaf' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('validates a PARTIAL price update against the STORED row', async () => {
      // The whole trap of a partial update: `minPricePerSeat: 9000` looks fine
      // on its own, and only breaks the invariant once merged with the stored
      // suggestion of 6000. Validating the payload alone would let it through.
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
        ...BAND,
      });

      await expect(service.update('c1', { minPricePerSeat: 9000 })).rejects.toBeInstanceOf(
        BadRequestException,
      );
      expect(prisma.corridor.update).not.toHaveBeenCalled();
    });

    it('rejects lowering max below the stored suggestion', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
        ...BAND,
      });

      await expect(service.update('c1', { maxPricePerSeat: 4000 })).rejects.toBeInstanceOf(
        BadRequestException,
      );
      expect(prisma.corridor.update).not.toHaveBeenCalled();
    });

    it('accepts a coherent all-three price update', async () => {
      prisma.corridor.findUnique.mockResolvedValue({
        id: 'c1',
        originCity: 'Najaf',
        destCity: 'Karbala',
        ...BAND,
      });

      await service.update('c1', {
        minPricePerSeat: 8000,
        suggestedPricePerSeat: 12000,
        maxPricePerSeat: 20000,
      });

      expect(prisma.corridor.update.mock.calls[0][0].data).toMatchObject({
        minPricePerSeat: 8000,
        suggestedPricePerSeat: 12000,
        maxPricePerSeat: 20000,
      });
    });
  });
});
