import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { RatingService } from './rating.service';
import { PrismaService } from '../prisma/prisma.service';

describe('RatingService.create', () => {
  let prisma: any;
  let service: RatingService;

  // Trip driver's profile is 'drvProfile1' → owned by user 'driverUser'.
  const completedTrip = { id: 't1', status: TripStatus.COMPLETED, driverId: 'drvProfile1' };
  const dto = { tripId: 't1', toUserId: 'driverUser', score: 5, comment: 'good' };

  beforeEach(() => {
    prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(completedTrip) },
      driverProfile: { findUnique: jest.fn(), update: jest.fn() },
      seatBooking: { findFirst: jest.fn() },
      rating: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn((a: any) => Promise.resolve({ id: 'r1', ...a.data })),
        aggregate: jest.fn().mockResolvedValue({ _avg: { score: 4.5 }, _count: 2 }),
      },
    };
    service = new RatingService(prisma as PrismaService);
  });

  // rider 'riderUser' rates driver 'driverUser'; rider has a COMPLETED booking.
  function setupRiderRatesDriver() {
    prisma.driverProfile.findUnique.mockImplementation((args: any) => {
      if (args.where.id === 'drvProfile1') return Promise.resolve({ userId: 'driverUser' });
      if (args.where.userId === 'driverUser') return Promise.resolve({ id: 'drvProfile1' });
      return Promise.resolve(null);
    });
    prisma.seatBooking.findFirst.mockResolvedValue({ id: 'bk1' });
  }

  it('creates a rating (rider → driver) and denormalizes the driver average', async () => {
    setupRiderRatesDriver();
    const r = await service.create('riderUser', dto);
    expect(r.score).toBe(5);
    expect(prisma.rating.create).toHaveBeenCalled();
    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'drvProfile1' }, data: { ratingAvg: 4.5 } }),
    );
  });

  it('409 when rating before the trip is completed', async () => {
    prisma.trip.findUnique.mockResolvedValue({ ...completedTrip, status: TripStatus.EN_ROUTE });
    await expect(service.create('riderUser', dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('400 when rating yourself', async () => {
    await expect(
      service.create('driverUser', { ...dto, toUserId: 'driverUser' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('403 when neither party is the trip driver', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ userId: 'someOtherDriver' });
    await expect(service.create('riderUser', dto)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('403 when the rider has no COMPLETED booking on the trip', async () => {
    prisma.driverProfile.findUnique.mockImplementation((args: any) =>
      args.where.id === 'drvProfile1' ? Promise.resolve({ userId: 'driverUser' }) : Promise.resolve(null),
    );
    prisma.seatBooking.findFirst.mockResolvedValue(null);
    await expect(service.create('riderUser', dto)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('409 on a duplicate rating (same trip/from/to)', async () => {
    setupRiderRatesDriver();
    prisma.rating.findFirst.mockResolvedValue({ id: 'existing' });
    await expect(service.create('riderUser', dto)).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.rating.create).not.toHaveBeenCalled();
  });

  it('404 when the trip is missing', async () => {
    prisma.trip.findUnique.mockResolvedValue(null);
    await expect(service.create('riderUser', dto)).rejects.toBeInstanceOf(NotFoundException);
  });
});
