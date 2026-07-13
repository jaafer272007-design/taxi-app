import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { BookingStatus, TripStatus } from '@prisma/client';
import { BookingService } from './booking.service';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';

function makeTx() {
  return {
    trip: {
      updateMany: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      update: jest.fn(),
    },
    seatBooking: {
      create: jest.fn((a: any) => Promise.resolve({ id: 'bk1', ...a.data })),
      updateMany: jest.fn(),
      findUniqueOrThrow: jest.fn(),
    },
  };
}

const futureTrip = {
  id: 't1',
  status: TripStatus.OPEN,
  departureTime: new Date(Date.now() + 3_600_000),
  driverId: 'drvX',
  vehicleId: 'v1',
  seatsAvailable: 3,
  pricePerSeat: 6000,
};

const dto = {
  tripId: 't1',
  pickup: { lat: 32, lng: 44, label: 'A' },
  dropoff: { lat: 32.1, lng: 44.1, label: 'B' },
  seatCount: 2,
};

describe('BookingService.book', () => {
  let prisma: any;
  let drivers: any;
  let tx: ReturnType<typeof makeTx>;
  let service: BookingService;

  beforeEach(() => {
    tx = makeTx();
    prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(futureTrip) },
      $transaction: jest.fn((cb: any) => cb(tx)),
    };
    drivers = { findProfileByUserId: jest.fn().mockResolvedValue(null) };
    service = new BookingService(prisma as PrismaService, drivers as DriverService);
  });

  it('404 when the trip is missing', async () => {
    prisma.trip.findUnique.mockResolvedValue(null);
    await expect(service.book('u1', dto)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('409 when the trip is not OPEN', async () => {
    prisma.trip.findUnique.mockResolvedValue({ ...futureTrip, status: TripStatus.LOCKED });
    await expect(service.book('u1', dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('409 when the trip has already departed', async () => {
    prisma.trip.findUnique.mockResolvedValue({ ...futureTrip, departureTime: new Date(Date.now() - 1000) });
    await expect(service.book('u1', dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('400 when the rider is the trip owner', async () => {
    drivers.findProfileByUserId.mockResolvedValue({ id: 'drvX' });
    await expect(service.book('u1', dto)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('409 when seatCount exceeds available seats', async () => {
    await expect(service.book('u1', { ...dto, seatCount: 4 })).rejects.toBeInstanceOf(ConflictException);
  });

  it('409 when the atomic reservation loses the race (count 0) and creates nothing', async () => {
    tx.trip.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.book('u1', dto)).rejects.toBeInstanceOf(ConflictException);
    expect(tx.seatBooking.create).not.toHaveBeenCalled();
  });

  it('reserves atomically and creates a CONFIRMED booking with the correct fare', async () => {
    tx.trip.updateMany.mockResolvedValue({ count: 1 });
    tx.trip.findUniqueOrThrow.mockResolvedValue({ ...futureTrip, seatsAvailable: 1 }); // 3 - 2

    const bk = await service.book('u1', dto);

    expect(tx.trip.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: 't1', status: TripStatus.OPEN, seatsAvailable: { gte: 2 } }),
        data: { seatsAvailable: { decrement: 2 } },
      }),
    );
    expect(bk.fare).toBe(12000);
    expect(bk.status).toBe(BookingStatus.CONFIRMED);
    expect(tx.trip.update).not.toHaveBeenCalled(); // still seats left → not locked
  });

  it('locks the trip when the last seats are taken (seatsAvailable → 0)', async () => {
    tx.trip.updateMany.mockResolvedValue({ count: 1 });
    tx.trip.findUniqueOrThrow.mockResolvedValue({ ...futureTrip, seatsAvailable: 0 });

    await service.book('u1', { ...dto, seatCount: 3 });

    expect(tx.trip.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 't1' }, data: { status: TripStatus.LOCKED } }),
    );
  });
});

describe('BookingService.cancel', () => {
  let prisma: any;
  let tx: ReturnType<typeof makeTx>;
  let service: BookingService;

  const soonTrip = (over: any = {}) => ({
    id: 't1',
    status: TripStatus.OPEN,
    departureTime: new Date(Date.now() + 3_600_000),
    ...over,
  });
  const booking = (over: any = {}) => ({
    id: 'bk1',
    riderId: 'u1',
    status: BookingStatus.CONFIRMED,
    seatCount: 2,
    trip: soonTrip(),
    ...over,
  });

  beforeEach(() => {
    tx = makeTx();
    prisma = {
      seatBooking: { findUnique: jest.fn() },
      $transaction: jest.fn((cb: any) => cb(tx)),
    };
    service = new BookingService(prisma as PrismaService, {} as DriverService);
  });

  it('404 when the booking is missing', async () => {
    prisma.seatBooking.findUnique.mockResolvedValue(null);
    await expect(service.cancel('u1', 'bk1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('403 when the caller is not the owner', async () => {
    prisma.seatBooking.findUnique.mockResolvedValue(booking({ riderId: 'someone' }));
    await expect(service.cancel('u1', 'bk1')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('409 when past the 15-minute cutoff', async () => {
    prisma.seatBooking.findUnique.mockResolvedValue(
      booking({ trip: soonTrip({ departureTime: new Date(Date.now() + 5 * 60_000) }) }),
    );
    await expect(service.cancel('u1', 'bk1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('returns the seat and reopens a LOCKED, not-departed trip', async () => {
    prisma.seatBooking.findUnique.mockResolvedValue(booking({ trip: soonTrip({ status: TripStatus.LOCKED }) }));
    tx.seatBooking.updateMany.mockResolvedValue({ count: 1 });
    tx.trip.findUniqueOrThrow.mockResolvedValue(soonTrip({ status: TripStatus.LOCKED }));
    tx.seatBooking.findUniqueOrThrow.mockResolvedValue(booking({ status: BookingStatus.CANCELLED }));

    await service.cancel('u1', 'bk1');

    expect(tx.trip.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { seatsAvailable: { increment: 2 } } }),
    );
    expect(tx.trip.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { status: TripStatus.OPEN } }),
    );
  });

  it('409 on a double-cancel race (updateMany count 0)', async () => {
    prisma.seatBooking.findUnique.mockResolvedValue(booking());
    tx.seatBooking.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.cancel('u1', 'bk1')).rejects.toBeInstanceOf(ConflictException);
  });
});
