import { BookingStatus, TripStatus } from '@prisma/client';
import { expireStaleTrips, TripExpiryStore } from './trip-expiry';
import { DEPART_NOW_WINDOW_MINUTES } from './trip-window';

const MINUTE = 60_000;
const NOW = new Date('2026-08-05T09:00:00.000Z');

function makeStore(stale: { id: string }[], liveBookings: { tripId: string }[]): TripExpiryStore & {
  updates: { where: any; data: any }[];
} {
  const updates: { where: any; data: any }[] = [];
  return {
    updates,
    trip: {
      findMany: jest.fn().mockResolvedValue(stale),
      updateMany: jest.fn((args: any) => {
        updates.push(args);
        return Promise.resolve({ count: args.where.id.in.length });
      }),
    },
    seatBooking: {
      findMany: jest.fn().mockResolvedValue(liveBookings),
    },
  };
}

describe('expireStaleTrips', () => {
  it('does nothing when no trip has expired', async () => {
    const store = makeStore([], []);
    expect(await expireStaleTrips(store, NOW)).toEqual({ locked: 0, cancelled: 0 });
    expect(store.trip.updateMany).not.toHaveBeenCalled();
    // …and does not go looking for bookings it has no use for.
    expect(store.seatBooking.findMany).not.toHaveBeenCalled();
  });

  it('CANCELS an expired trip nobody booked', async () => {
    // LOCKED would render as «مكتملة الحجز» — "fully booked" — on a trip that
    // carried no one. CANCELLED is what actually happened.
    const store = makeStore([{ id: 'empty' }], []);

    expect(await expireStaleTrips(store, NOW)).toEqual({ locked: 0, cancelled: 1 });
    expect(store.updates).toEqual([
      { where: { id: { in: ['empty'] }, status: TripStatus.OPEN }, data: { status: TripStatus.CANCELLED } },
    ]);
  });

  it('LOCKS an expired trip that has riders', async () => {
    const store = makeStore([{ id: 'booked' }], [{ tripId: 'booked' }]);

    expect(await expireStaleTrips(store, NOW)).toEqual({ locked: 1, cancelled: 0 });
    expect(store.updates).toEqual([
      { where: { id: { in: ['booked'] }, status: TripStatus.OPEN }, data: { status: TripStatus.LOCKED } },
    ]);
  });

  it('splits a mixed batch by whether anyone actually booked', async () => {
    const store = makeStore([{ id: 'a' }, { id: 'b' }, { id: 'c' }], [{ tripId: 'b' }]);

    expect(await expireStaleTrips(store, NOW)).toEqual({ locked: 1, cancelled: 2 });
    const byStatus = Object.fromEntries(store.updates.map((u) => [u.data.status, u.where.id.in]));
    expect(byStatus[TripStatus.LOCKED]).toEqual(['b']);
    expect(byStatus[TripStatus.CANCELLED]).toEqual(['a', 'c']);
  });

  it('only counts CONFIRMED and ONBOARD bookings as riders', async () => {
    // A rider who booked and then cancelled must not keep an empty trip alive
    // and mislabel it as "fully booked".
    const store = makeStore([{ id: 't' }], []);
    await expireStaleTrips(store, NOW);

    const statusFilter = (store.seatBooking.findMany as jest.Mock).mock.calls[0][0].where.status.in;
    expect(statusFilter).toEqual([BookingStatus.CONFIRMED, BookingStatus.ONBOARD]);
  });

  it('re-asserts status OPEN in the write, so a concurrent start is not clobbered', async () => {
    // Between the read and the write the driver may have hit «ابدأ الرحلة».
    // Without this guard the sweep would drag an EN_ROUTE trip back to LOCKED.
    const store = makeStore([{ id: 't' }], [{ tripId: 't' }]);
    await expireStaleTrips(store, NOW);

    expect(store.updates[0].where.status).toBe(TripStatus.OPEN);
  });

  it('asks only for trips that are OPEN and past their window', async () => {
    const store = makeStore([], []);
    await expireStaleTrips(store, NOW);

    const where = (store.trip.findMany as jest.Mock).mock.calls[0][0].where;
    expect(where.status).toBe(TripStatus.OPEN);
    // The departNow branch reaches back exactly one window, no further.
    const departNowBranch = where.OR.find((b: any) => b.departNow === true);
    expect(departNowBranch.departureTime.lte).toEqual(
      new Date(NOW.getTime() - DEPART_NOW_WINDOW_MINUTES * MINUTE),
    );
    // The scheduled branch reaches back not at all.
    const scheduledBranch = where.OR.find((b: any) => b.departNow === false);
    expect(scheduledBranch.departureTime.lte).toEqual(NOW);
  });
});
