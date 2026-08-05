import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { BookingStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { TripContactService } from './trip-contact.service';

/**
 * Unit cover for the parts of [TripContactService] a mock CAN speak to: which
 * branch a caller lands in, the shape that comes back, and the defensive path
 * where a row's user is gone.
 *
 * It deliberately does NOT claim to test the entitlement boundary. That rule
 * lives inside a Prisma `where`, and a mocked `findFirst` returns whatever the
 * test handed it — so "a cancelled booking is refused" can only be proved
 * against a real database. See `trip-contact.int-spec.ts`.
 *
 * What IS asserted here about the filter is that the query is *asked* with the
 * right shape (`status: { not: CANCELLED }`, scoped to the trip). Shape plus
 * effect: this file has the first half, the integration spec the second.
 */
describe('TripContactService', () => {
  let prisma: {
    trip: { findUnique: jest.Mock };
    seatBooking: { findFirst: jest.Mock; findMany: jest.Mock };
    user: { findMany: jest.Mock };
    driverProfile: { findUnique: jest.Mock };
  };
  let drivers: { findProfileByUserId: jest.Mock };
  let service: TripContactService;

  const TRIP = { id: 't1', driverId: 'drv1' };

  beforeEach(() => {
    prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(TRIP) },
      seatBooking: { findFirst: jest.fn(), findMany: jest.fn() },
      user: { findMany: jest.fn() },
      driverProfile: { findUnique: jest.fn() },
    };
    drivers = { findProfileByUserId: jest.fn().mockResolvedValue(null) };
    service = new TripContactService(
      prisma as unknown as PrismaService,
      drivers as unknown as DriverService,
    );
  });

  it('404s an unknown trip before asking anything about the caller', async () => {
    prisma.trip.findUnique.mockResolvedValue(null);

    await expect(service.listContacts('u1', 'nope')).rejects.toBeInstanceOf(NotFoundException);
    expect(drivers.findProfileByUserId).not.toHaveBeenCalled();
  });

  it('403s a caller who is neither the driver nor a booked rider', async () => {
    prisma.seatBooking.findFirst.mockResolvedValue(null);

    await expect(service.listContacts('u1', 't1')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('excludes cancelled bookings when asking whether the caller is a rider', async () => {
    // Shape only — that this filter WORKS is the integration spec's job.
    prisma.seatBooking.findFirst.mockResolvedValue(null);

    await expect(service.listContacts('u1', 't1')).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.seatBooking.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          tripId: 't1',
          riderId: 'u1',
          status: { not: BookingStatus.CANCELLED },
        },
      }),
    );
  });

  it('gives a booked rider the driver, tagged with their own booking', async () => {
    prisma.seatBooking.findFirst.mockResolvedValue({ id: 'b9' });
    prisma.driverProfile.findUnique.mockResolvedValue({
      user: { id: 'driver-user', name: 'أبو علي', phone: '+9647701234567' },
    });

    const result = await service.listContacts('rider-user', 't1');

    expect(result).toEqual({
      role: 'RIDER',
      contacts: [
        {
          userId: 'driver-user',
          name: 'أبو علي',
          phone: '+9647701234567',
          bookingId: 'b9',
        },
      ],
    });
  });

  it('gives the owning driver one contact per live booking, in booking order', async () => {
    drivers.findProfileByUserId.mockResolvedValue({ id: 'drv1' });
    prisma.seatBooking.findMany.mockResolvedValue([
      { id: 'b1', riderId: 'r1' },
      { id: 'b2', riderId: 'r2' },
    ]);
    prisma.user.findMany.mockResolvedValue([
      { id: 'r2', name: 'ثانية', phone: '+9647702222222' },
      { id: 'r1', name: 'أولى', phone: '+9647701111111' },
    ]);

    const result = await service.listContacts('driver-user', 't1');

    expect(result.role).toBe('DRIVER');
    // Ordered by the BOOKINGS, not by whatever order the user join came back
    // in — the driver's list must line up with the bookings list on screen.
    expect(result.contacts).toEqual([
      { userId: 'r1', name: 'أولى', phone: '+9647701111111', bookingId: 'b1' },
      { userId: 'r2', name: 'ثانية', phone: '+9647702222222', bookingId: 'b2' },
    ]);
  });

  it('drops a booking whose user row is gone rather than emitting an empty phone', async () => {
    // An empty phone would render a call button that dials nothing.
    drivers.findProfileByUserId.mockResolvedValue({ id: 'drv1' });
    prisma.seatBooking.findMany.mockResolvedValue([
      { id: 'b1', riderId: 'ghost' },
      { id: 'b2', riderId: 'r2' },
    ]);
    prisma.user.findMany.mockResolvedValue([{ id: 'r2', name: null, phone: '+9647702222222' }]);

    const result = await service.listContacts('driver-user', 't1');

    expect(result.contacts).toEqual([
      { userId: 'r2', name: null, phone: '+9647702222222', bookingId: 'b2' },
    ]);
  });

  it('treats a driver who owns a DIFFERENT trip as a stranger here', async () => {
    drivers.findProfileByUserId.mockResolvedValue({ id: 'someone-else' });
    prisma.seatBooking.findFirst.mockResolvedValue(null);

    await expect(service.listContacts('other-driver', 't1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});
