import { BookingStatus, TripStatus } from '@prisma/client';
import { expiredTripFilter } from './trip-window';

/** The slice of PrismaClient this needs — so it is testable without a database. */
export interface TripExpiryStore {
  trip: {
    findMany(args: unknown): Promise<{ id: string }[]>;
    updateMany(args: unknown): Promise<{ count: number }>;
  };
  seatBooking: {
    findMany(args: unknown): Promise<{ tripId: string }[]>;
  };
}

export interface ExpiryResult {
  /** Expired trips that had riders — moved to LOCKED. */
  locked: number;
  /** Expired trips nobody booked — moved to CANCELLED. */
  cancelled: number;
}

/**
 * Retire trips that are no longer catchable but are still sitting OPEN.
 *
 * This resolves the `TODO(Step 4/5)` that sat on the departNow window. Search
 * already hides an expired trip — that is the `catchableTripFilter` — but
 * without this the row stays OPEN forever, so the driver's رحلاتي keeps
 * offering «ابدأ الرحلة» on a trip whose window shut hours ago.
 *
 * ## Which end state
 *
 * The Phase 1 state machine (§3) is `OPEN → LOCKED (امتلأ أو حان الوقت) →
 * EN_ROUTE`, with `CANCELLED` available any time before EN_ROUTE. So:
 *
 *  - **Had riders → LOCKED.** The time came; the trip is no longer taking
 *    bookings and the driver carries on with the riders they have.
 *  - **Nobody booked → CANCELLED.** LOCKED would render as «مكتملة الحجز» in
 *    رحلاتي — "fully booked" — which is the opposite of what happened. A trip
 *    that lapsed empty never ran, and CANCELLED says so.
 *
 * Scheduled trips are swept on the same rule. Their departure passing leaves
 * them just as stuck, and it is the same sentence in the state machine.
 *
 * ## How it runs
 *
 * Called from the read paths that would otherwise show stale state: rider
 * search and the driver's own trip list. There is no scheduler in this service
 * (`@nestjs/schedule` is not a dependency, and adding a background timer for
 * this alone is more moving parts than the problem is worth at Phase 1 scale).
 * The queries are narrow and indexed on status, so this is cheap; if the
 * service ever grows a real job runner, call this from there instead and drop
 * it from the read paths.
 */
export async function expireStaleTrips(
  store: TripExpiryStore,
  now: Date = new Date(),
): Promise<ExpiryResult> {
  const stale = await store.trip.findMany({
    where: { status: TripStatus.OPEN, ...expiredTripFilter(now) },
    select: { id: true },
  });
  if (stale.length === 0) return { locked: 0, cancelled: 0 };

  const staleIds = stale.map((t) => t.id);

  // A rider who booked and then cancelled does not keep the trip alive.
  const live = await store.seatBooking.findMany({
    where: {
      tripId: { in: staleIds },
      status: { in: [BookingStatus.CONFIRMED, BookingStatus.ONBOARD] },
    },
    select: { tripId: true },
  });
  const withRiders = new Set(live.map((b) => b.tripId));
  const emptyIds = staleIds.filter((id) => !withRiders.has(id));
  const bookedIds = staleIds.filter((id) => withRiders.has(id));

  // Both updates re-assert `status: OPEN` so a trip someone started or
  // cancelled between the read above and this write is left alone.
  const [locked, cancelled] = await Promise.all([
    bookedIds.length
      ? store.trip.updateMany({
          where: { id: { in: bookedIds }, status: TripStatus.OPEN },
          data: { status: TripStatus.LOCKED },
        })
      : Promise.resolve({ count: 0 }),
    emptyIds.length
      ? store.trip.updateMany({
          where: { id: { in: emptyIds }, status: TripStatus.OPEN },
          data: { status: TripStatus.CANCELLED },
        })
      : Promise.resolve({ count: 0 }),
  ]);

  return { locked: locked.count, cancelled: cancelled.count };
}
