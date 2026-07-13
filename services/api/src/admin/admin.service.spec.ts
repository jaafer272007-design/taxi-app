import { NotFoundException } from '@nestjs/common';
import { DriverStatus } from '@prisma/client';
import { AdminService } from './admin.service';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationService } from '../notification/notification.service';

describe('AdminService (approval + notifications)', () => {
  let prisma: {
    driverProfile: { findUnique: jest.Mock; update: jest.Mock; findMany: jest.Mock };
  };
  let notifications: { send: jest.Mock };
  let service: AdminService;

  beforeEach(() => {
    prisma = {
      driverProfile: {
        findUnique: jest.fn(),
        update: jest.fn(),
        findMany: jest.fn(),
      },
    };
    notifications = { send: jest.fn() };
    service = new AdminService(
      prisma as unknown as PrismaService,
      notifications as unknown as NotificationService,
    );
  });

  it('approve() sets APPROVED, clears rejection reason, and notifies the driver', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.REJECTED });
    prisma.driverProfile.update.mockResolvedValue({
      id: 'd1',
      status: DriverStatus.APPROVED,
      user: { id: 'driverU' },
    });

    await service.approve('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'd1' },
        data: { status: DriverStatus.APPROVED, rejectionReason: null },
      }),
    );
    expect(notifications.send).toHaveBeenCalledWith(
      'driverU',
      expect.objectContaining({ data: expect.objectContaining({ type: 'driver.approved' }) }),
    );
  });

  it('approve() throws NotFound and does not update when the driver is missing', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue(null);
    await expect(service.approve('missing')).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.driverProfile.update).not.toHaveBeenCalled();
    expect(notifications.send).not.toHaveBeenCalled();
  });

  it('reject() persists the reason and notifies the driver', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.PENDING });
    prisma.driverProfile.update.mockResolvedValue({
      id: 'd1',
      status: DriverStatus.REJECTED,
      user: { id: 'driverU' },
    });

    await service.reject('d1', 'blurry documents');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'd1' },
        data: { status: DriverStatus.REJECTED, rejectionReason: 'blurry documents' },
      }),
    );
    expect(notifications.send).toHaveBeenCalledWith(
      'driverU',
      expect.objectContaining({ data: expect.objectContaining({ type: 'driver.rejected' }) }),
    );
  });

  it('reject() with no reason stores null', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.PENDING });
    prisma.driverProfile.update.mockResolvedValue({
      id: 'd1',
      status: DriverStatus.REJECTED,
      user: { id: 'driverU' },
    });

    await service.reject('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { status: DriverStatus.REJECTED, rejectionReason: null },
      }),
    );
  });

  it('suspend() sets SUSPENDED without touching rejectionReason and does not notify', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.APPROVED });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.SUSPENDED });

    await service.suspend('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'd1' }, data: { status: DriverStatus.SUSPENDED } }),
    );
    expect(notifications.send).not.toHaveBeenCalled();
  });
});

describe('AdminService dashboard', () => {
  const notif = { send: jest.fn() } as unknown as NotificationService;

  it('getDashboard aggregates the right counts', async () => {
    const prisma = {
      user: { count: jest.fn().mockResolvedValue(10) },
      driverProfile: {
        groupBy: jest.fn().mockResolvedValue([
          { status: 'APPROVED', _count: { _all: 3 } },
          { status: 'PENDING', _count: { _all: 2 } },
        ]),
      },
      trip: {
        groupBy: jest.fn().mockResolvedValue([
          { status: 'OPEN', _count: { _all: 4 } },
          { status: 'SETTLED', _count: { _all: 1 } },
        ]),
        count: jest.fn().mockResolvedValue(2),
      },
      seatBooking: { count: jest.fn().mockResolvedValue(7) },
      earningsRecord: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: 50000 } }) },
    };
    const svc = new AdminService(prisma as unknown as PrismaService, notif);

    const d = await svc.getDashboard();

    expect(d.riders).toBe(10);
    expect(d.drivers).toEqual({ total: 5, byStatus: { APPROVED: 3, PENDING: 2 } });
    expect(d.trips.total).toBe(5);
    expect(d.trips.today).toBe(2);
    expect(d.bookings).toBe(7);
    expect(d.earningsTotal).toBe(50000);
  });

  it('listTrips paginates and enriches driver + booking counts', async () => {
    const prisma = {
      trip: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 't1',
            status: 'OPEN',
            departureTime: new Date(),
            seatsTotal: 3,
            seatsAvailable: 1,
            pricePerSeat: 6000,
            driverId: 'drv1',
            corridor: { originCity: 'Najaf', destCity: 'Karbala' },
            _count: { bookings: 2 },
          },
        ]),
        count: jest.fn().mockResolvedValue(1),
      },
      driverProfile: {
        findMany: jest.fn().mockResolvedValue([
          { id: 'drv1', ratingAvg: 4.5, user: { phone: '+9647700000001', name: 'Ali' } },
        ]),
      },
    };
    const svc = new AdminService(prisma as unknown as PrismaService, notif);

    const res = await svc.listTrips({ page: 1, perPage: 20 } as any);

    expect(res.total).toBe(1);
    expect(res.items[0].bookingCount).toBe(2);
    expect(res.items[0].driver).toEqual({ phone: '+9647700000001', name: 'Ali', ratingAvg: 4.5 });
    expect(res.items[0].corridor).toEqual({ originCity: 'Najaf', destCity: 'Karbala' });
  });
});
