import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { DriverStatus, TripCreatedBy, TripStatus } from '@prisma/client';
import { TripService } from './trip.service';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';

describe('TripService.createTrip', () => {
  let prisma: { vehicle: { findUnique: jest.Mock }; trip: { create: jest.Mock } };
  let drivers: { assertApprovedDriver: jest.Mock; findProfileByUserId: jest.Mock };
  let corridors: { findById: jest.Mock };
  let service: TripService;

  const approvedProfile = { id: 'drv1', status: DriverStatus.APPROVED };

  beforeEach(() => {
    prisma = {
      vehicle: { findUnique: jest.fn() },
      trip: { create: jest.fn((arg) => Promise.resolve({ id: 't1', ...arg.data })) },
    };
    drivers = {
      assertApprovedDriver: jest.fn().mockResolvedValue(approvedProfile),
      findProfileByUserId: jest.fn(),
    };
    corridors = { findById: jest.fn() };
    service = new TripService(
      prisma as unknown as PrismaService,
      drivers as unknown as DriverService,
      corridors as unknown as CorridorService,
    );
  });

  it('propagates the approved-driver gate (403) and never creates a trip', async () => {
    drivers.assertApprovedDriver.mockRejectedValue(new ForbiddenException('not approved'));
    await expect(
      service.createTrip('u1', { corridorId: 'c1', departNow: true, seatsTotal: 3 }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.trip.create).not.toHaveBeenCalled();
  });

  it('rejects seatsTotal greater than the vehicle capacity', async () => {
    prisma.vehicle.findUnique.mockResolvedValue({ id: 'v1', seats: 4 });
    await expect(
      service.createTrip('u1', { corridorId: 'c1', departNow: true, seatsTotal: 5 }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.trip.create).not.toHaveBeenCalled();
  });

  it('creates an OPEN trip, snapshots corridor price, seatsAvailable = seatsTotal', async () => {
    prisma.vehicle.findUnique.mockResolvedValue({ id: 'v1', seats: 4 });
    corridors.findById.mockResolvedValue({ id: 'c1', active: true, pricePerSeat: 7000 });

    await service.createTrip('u1', { corridorId: 'c1', departNow: true, seatsTotal: 4 });

    const data = prisma.trip.create.mock.calls[0][0].data;
    expect(data).toMatchObject({
      corridorId: 'c1',
      driverId: 'drv1',
      vehicleId: 'v1',
      seatsTotal: 4,
      seatsAvailable: 4,
      pricePerSeat: 7000,
      status: TripStatus.OPEN,
      createdBy: TripCreatedBy.DRIVER,
      departNow: true,
    });
  });

  it('rejects an inactive corridor', async () => {
    prisma.vehicle.findUnique.mockResolvedValue({ id: 'v1', seats: 4 });
    corridors.findById.mockResolvedValue({ id: 'c1', active: false, pricePerSeat: 5000 });
    await expect(
      service.createTrip('u1', { corridorId: 'c1', departNow: true, seatsTotal: 2 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('404s a missing corridor', async () => {
    prisma.vehicle.findUnique.mockResolvedValue({ id: 'v1', seats: 4 });
    corridors.findById.mockResolvedValue(null);
    await expect(
      service.createTrip('u1', { corridorId: 'nope', departNow: true, seatsTotal: 2 }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects a scheduled trip whose departureTime is in the past', async () => {
    prisma.vehicle.findUnique.mockResolvedValue({ id: 'v1', seats: 4 });
    corridors.findById.mockResolvedValue({ id: 'c1', active: true, pricePerSeat: 5000 });
    const past = new Date(Date.now() - 60_000).toISOString();
    await expect(
      service.createTrip('u1', { corridorId: 'c1', departureTime: past, seatsTotal: 2 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects sending BOTH departNow and departureTime (EITHER/OR contract)', async () => {
    prisma.vehicle.findUnique.mockResolvedValue({ id: 'v1', seats: 4 });
    corridors.findById.mockResolvedValue({ id: 'c1', active: true, pricePerSeat: 5000 });
    const future = new Date(Date.now() + 3_600_000).toISOString();
    await expect(
      service.createTrip('u1', { corridorId: 'c1', departNow: true, departureTime: future, seatsTotal: 2 }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.trip.create).not.toHaveBeenCalled();
  });
});
