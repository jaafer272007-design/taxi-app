import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import {
  BookingStatus,
  DriverStatus,
  PaymentStatus,
  TripCreatedBy,
  TripStatus,
} from '@prisma/client';
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
      { send: jest.fn() } as any,
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

describe('TripService.updateTrip (booking-aware seat guard)', () => {
  let prisma: any;
  let drivers: any;
  let service: TripService;

  // seatsTotal 4, seatsAvailable 1 → 3 seats already booked.
  const openTrip = { id: 't1', status: TripStatus.OPEN, driverId: 'drv1', seatsTotal: 4, seatsAvailable: 1 };

  beforeEach(() => {
    prisma = {
      trip: {
        findUnique: jest.fn().mockResolvedValue(openTrip),
        update: jest.fn((a) => Promise.resolve({ ...openTrip, ...a.data })),
      },
      vehicle: { findUnique: jest.fn().mockResolvedValue({ id: 'v1', seats: 4 }) },
    };
    drivers = { findProfileByUserId: jest.fn().mockResolvedValue({ id: 'drv1' }) };
    service = new TripService(
      prisma as PrismaService,
      drivers as DriverService,
      {} as CorridorService,
      { send: jest.fn() } as any,
    );
  });

  it('rejects reducing seatsTotal below already-booked seats', async () => {
    await expect(service.updateTrip('u1', 't1', { seatsTotal: 2 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.trip.update).not.toHaveBeenCalled();
  });

  it('preserves the booked count when resizing (seatsAvailable = new total - booked)', async () => {
    await service.updateTrip('u1', 't1', { seatsTotal: 4 });
    expect(prisma.trip.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 't1' },
        data: expect.objectContaining({ seatsTotal: 4, seatsAvailable: 1 }),
      }),
    );
  });

  it('rejects PATCH on a non-OPEN trip', async () => {
    prisma.trip.findUnique.mockResolvedValue({ ...openTrip, status: TripStatus.LOCKED });
    await expect(service.updateTrip('u1', 't1', { seatsTotal: 3 })).rejects.toBeInstanceOf(
      ConflictException,
    );
  });
});

describe('TripService lifecycle (start / complete)', () => {
  let prisma: any;
  let drivers: any;
  let notifications: any;
  let service: TripService;
  const approved = { id: 'drv1', status: DriverStatus.APPROVED };

  beforeEach(() => {
    prisma = {
      trip: {
        findUnique: jest.fn(),
        update: jest.fn((a) => Promise.resolve({ id: 't1', ...a.data })),
      },
      seatBooking: { findMany: jest.fn().mockResolvedValue([]), update: jest.fn() },
      earningsRecord: { create: jest.fn() },
      driverProfile: { update: jest.fn() },
      // tx uses the same mock object
      $transaction: jest.fn((cb: any) => cb(prisma)),
    };
    drivers = { findProfileByUserId: jest.fn().mockResolvedValue(approved) };
    notifications = { send: jest.fn() };
    service = new TripService(
      prisma as PrismaService,
      drivers as DriverService,
      {} as CorridorService,
      notifications,
    );
  });

  describe('start', () => {
    it('moves OPEN → EN_ROUTE and notifies confirmed riders (trip.started)', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.OPEN, driverId: 'drv1' });
      prisma.seatBooking.findMany.mockResolvedValue([{ riderId: 'r1' }]);
      await service.start('u1', 't1');
      expect(prisma.trip.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 't1' }, data: { status: TripStatus.EN_ROUTE } }),
      );
      expect(notifications.send).toHaveBeenCalledWith(
        'r1',
        expect.objectContaining({ data: expect.objectContaining({ type: 'trip.started' }) }),
      );
    });

    it('moves LOCKED → EN_ROUTE', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.LOCKED, driverId: 'drv1' });
      await service.start('u1', 't1');
      expect(prisma.trip.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: TripStatus.EN_ROUTE } }),
      );
    });

    it('409 from a wrong status (e.g. COMPLETED)', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.COMPLETED, driverId: 'drv1' });
      await expect(service.start('u1', 't1')).rejects.toBeInstanceOf(ConflictException);
    });

    it('403 when the caller is not the trip owner', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.OPEN, driverId: 'other' });
      await expect(service.start('u1', 't1')).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('403 when the driver is not APPROVED', async () => {
      drivers.findProfileByUserId.mockResolvedValue({ id: 'drv1', status: DriverStatus.SUSPENDED });
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.OPEN, driverId: 'drv1' });
      await expect(service.start('u1', 't1')).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('complete', () => {
    it('409 when the trip is not EN_ROUTE', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.OPEN, driverId: 'drv1' });
      await expect(service.complete('u1', 't1')).rejects.toBeInstanceOf(ConflictException);
    });

    it('settles riders, excludes NO_SHOW from earnings, bumps tripsDone, ends SETTLED', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.EN_ROUTE, driverId: 'drv1' });
      prisma.seatBooking.findMany.mockResolvedValue([
        { id: 'b1', riderId: 'r1', status: BookingStatus.ONBOARD, fare: 6000 },
        { id: 'b2', riderId: 'r2', status: BookingStatus.CONFIRMED, fare: 12000 }, // default rode
        { id: 'b3', riderId: 'r3', status: BookingStatus.NO_SHOW, fare: 6000 }, // excluded
        { id: 'b4', riderId: 'r4', status: BookingStatus.CANCELLED, fare: 6000 }, // untouched
      ]);

      await service.complete('u1', 't1');

      expect(prisma.seatBooking.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'b1' },
          data: { status: BookingStatus.COMPLETED, paymentStatus: PaymentStatus.COLLECTED },
        }),
      );
      expect(prisma.seatBooking.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'b2' } }),
      );
      const settledIds = prisma.seatBooking.update.mock.calls.map((c: any) => c[0].where.id);
      expect(settledIds).not.toContain('b3');
      expect(settledIds).not.toContain('b4');

      expect(prisma.earningsRecord.create).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ driverId: 'drv1', tripId: 't1', amount: 18000 }) }),
      );
      expect(prisma.driverProfile.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { tripsDone: { increment: 1 } } }),
      );
      expect(prisma.trip.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: TripStatus.SETTLED } }),
      );
      // trip.completed → riders notified after commit
      expect(notifications.send).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ data: expect.objectContaining({ type: 'trip.completed' }) }),
      );
    });

    it('records no earnings when nobody rode (all NO_SHOW) but still SETTLES', async () => {
      prisma.trip.findUnique.mockResolvedValue({ id: 't1', status: TripStatus.EN_ROUTE, driverId: 'drv1' });
      prisma.seatBooking.findMany.mockResolvedValue([
        { id: 'b1', status: BookingStatus.NO_SHOW, fare: 6000 },
      ]);

      await service.complete('u1', 't1');

      expect(prisma.earningsRecord.create).not.toHaveBeenCalled();
      expect(prisma.trip.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: TripStatus.SETTLED } }),
      );
    });
  });
});

describe('TripService.listBookings (driver view of its bookings)', () => {
  let prisma: any;
  let drivers: any;
  let service: TripService;

  beforeEach(() => {
    prisma = {
      trip: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ id: 't1', driverId: 'drv1', status: TripStatus.EN_ROUTE }),
      },
      seatBooking: { findMany: jest.fn() },
      user: { findMany: jest.fn() },
    };
    drivers = {
      findProfileByUserId: jest.fn().mockResolvedValue({ id: 'drv1', status: DriverStatus.APPROVED }),
    };
    service = new TripService(
      prisma as PrismaService,
      drivers as DriverService,
      {} as CorridorService,
      { send: jest.fn() } as any,
    );
  });

  it('403 when the caller does not own the trip (never reads bookings)', async () => {
    prisma.trip.findUnique.mockResolvedValue({ id: 't1', driverId: 'other' });
    await expect(service.listBookings('u1', 't1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.seatBooking.findMany).not.toHaveBeenCalled();
  });

  it('404 when the trip does not exist', async () => {
    prisma.trip.findUnique.mockResolvedValue(null);
    await expect(service.listBookings('u1', 't1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('returns [] for a trip with no bookings and skips the rider lookup', async () => {
    prisma.seatBooking.findMany.mockResolvedValue([]);
    await expect(service.listBookings('u1', 't1')).resolves.toEqual([]);
    expect(prisma.user.findMany).not.toHaveBeenCalled();
  });

  it('bulk-joins each rider name and surfaces seatCount/pickup/dropoff/status/fare', async () => {
    prisma.seatBooking.findMany.mockResolvedValue([
      {
        id: 'b1',
        riderId: 'r1',
        seatCount: 2,
        pickupLabel: 'كراج النجف',
        dropoffLabel: 'باب القبلة',
        fare: 12000,
        status: BookingStatus.CONFIRMED,
        paymentStatus: PaymentStatus.PENDING,
      },
      {
        id: 'b2',
        riderId: 'r2',
        seatCount: 1,
        pickupLabel: 'دوار الثورة',
        dropoffLabel: 'الحرم',
        fare: 6000,
        status: BookingStatus.ONBOARD,
        paymentStatus: PaymentStatus.PENDING,
      },
    ]);
    prisma.user.findMany.mockResolvedValue([
      { id: 'r1', name: 'علي' },
      { id: 'r2', name: 'حسن' },
    ]);

    const rows = await service.listBookings('u1', 't1');

    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: { in: ['r1', 'r2'] } } }),
    );
    expect(rows).toEqual([
      {
        id: 'b1',
        riderId: 'r1',
        riderName: 'علي',
        seatCount: 2,
        pickupLabel: 'كراج النجف',
        dropoffLabel: 'باب القبلة',
        fare: 12000,
        status: BookingStatus.CONFIRMED,
        paymentStatus: PaymentStatus.PENDING,
      },
      {
        id: 'b2',
        riderId: 'r2',
        riderName: 'حسن',
        seatCount: 1,
        pickupLabel: 'دوار الثورة',
        dropoffLabel: 'الحرم',
        fare: 6000,
        status: BookingStatus.ONBOARD,
        paymentStatus: PaymentStatus.PENDING,
      },
    ]);
  });

  it('falls back to null when a rider has no name set', async () => {
    prisma.seatBooking.findMany.mockResolvedValue([
      {
        id: 'b1',
        riderId: 'r1',
        seatCount: 1,
        pickupLabel: 'A',
        dropoffLabel: 'B',
        fare: 6000,
        status: BookingStatus.CONFIRMED,
        paymentStatus: PaymentStatus.PENDING,
      },
    ]);
    prisma.user.findMany.mockResolvedValue([{ id: 'r1', name: null }]);
    const rows = await service.listBookings('u1', 't1');
    expect(rows[0].riderName).toBeNull();
  });
});
