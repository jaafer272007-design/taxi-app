import { Prisma } from '@prisma/client';
import {
  DEPART_NOW_WINDOW_MINUTES,
  catchableTripFilter,
  catchableUntil,
  expiredTripFilter,
  isCatchable,
  remainingWindowMs,
} from './trip-window';

/**
 * The rule that decides whether a rider can still catch a trip.
 *
 * The bug this file exists to prevent: `POST /trips` gave a departNow trip a
 * 30-minute validity window while search filtered on `departureTime > now`, so
 * a departNow trip — whose departureTime IS now — was excluded within a second
 * of being posted. Both halves were individually reasonable. Nothing tested
 * them together.
 */

const MINUTE = 60_000;
const NOW = new Date('2026-08-05T09:00:00.000Z');

const departNowTrip = (minutesAgo: number) => ({
  departNow: true,
  departureTime: new Date(NOW.getTime() - minutesAgo * MINUTE),
});

const scheduledTrip = (minutesFromNow: number) => ({
  departNow: false,
  departureTime: new Date(NOW.getTime() + minutesFromNow * MINUTE),
});

describe('isCatchable', () => {
  it('a departNow trip is catchable the instant it is posted', () => {
    // The exact live-testing report: post, then search seconds later.
    expect(isCatchable(departNowTrip(0), NOW)).toBe(true);
  });

  it('a departNow trip stays catchable through its window', () => {
    expect(isCatchable(departNowTrip(1), NOW)).toBe(true);
    expect(isCatchable(departNowTrip(15), NOW)).toBe(true);
    expect(isCatchable(departNowTrip(DEPART_NOW_WINDOW_MINUTES - 1), NOW)).toBe(true);
  });

  it('a departNow trip stops being catchable once the window closes', () => {
    expect(isCatchable(departNowTrip(DEPART_NOW_WINDOW_MINUTES), NOW)).toBe(false);
    expect(isCatchable(departNowTrip(DEPART_NOW_WINDOW_MINUTES + 1), NOW)).toBe(false);
    expect(isCatchable(departNowTrip(120), NOW)).toBe(false);
  });

  it('a SCHEDULED trip is still gone the moment its departure passes', () => {
    // The half of the rule that must NOT be relaxed: widening the bound for
    // every trip would resurrect timetabled trips that have genuinely left.
    expect(isCatchable(scheduledTrip(1), NOW)).toBe(true);
    expect(isCatchable(scheduledTrip(0), NOW)).toBe(false);
    expect(isCatchable(scheduledTrip(-1), NOW)).toBe(false);
    // Not even within what would be the departNow grace period.
    expect(isCatchable(scheduledTrip(-(DEPART_NOW_WINDOW_MINUTES - 1)), NOW)).toBe(false);
  });
});

describe('catchableUntil / remainingWindowMs', () => {
  it('a departNow trip runs to departure + the window', () => {
    expect(catchableUntil(departNowTrip(0))).toEqual(
      new Date(NOW.getTime() + DEPART_NOW_WINDOW_MINUTES * MINUTE),
    );
  });

  it('a scheduled trip runs to its departure', () => {
    expect(catchableUntil(scheduledTrip(90))).toEqual(new Date(NOW.getTime() + 90 * MINUTE));
  });

  it('reports the time left, floored at zero once expired', () => {
    expect(remainingWindowMs(departNowTrip(10), NOW)).toBe(
      (DEPART_NOW_WINDOW_MINUTES - 10) * MINUTE,
    );
    expect(remainingWindowMs(departNowTrip(999), NOW)).toBe(0);
  });
});

/**
 * The predicate and the Prisma filter are two encodings of ONE rule, used on
 * different sides of the database. Two encodings drifting apart is the whole
 * story of this bug, so they are checked against each other rather than each
 * being checked against its author's intent.
 */
describe('catchableTripFilter agrees with isCatchable', () => {
  /** Evaluate the Prisma OR-filter in memory, the way the DB would. */
  function matchesFilter(
    filter: Prisma.TripWhereInput,
    trip: { departNow: boolean; departureTime: Date },
  ): boolean {
    const branches = filter.OR as {
      departNow: boolean;
      departureTime: { gt?: Date; lte?: Date };
    }[];
    return branches.some((b) => {
      if (b.departNow !== trip.departNow) return false;
      if (b.departureTime.gt) return trip.departureTime.getTime() > b.departureTime.gt.getTime();
      if (b.departureTime.lte) return trip.departureTime.getTime() <= b.departureTime.lte.getTime();
      return false;
    });
  }

  const cases = [
    ...[0, 1, 15, 29, 30, 31, 120].map((m) => departNowTrip(m)),
    ...[-120, -31, -30, -1, 0, 1, 30, 120].map((m) => scheduledTrip(m)),
  ];

  it.each(cases)('same verdict for %j', (trip) => {
    expect(matchesFilter(catchableTripFilter(NOW), trip)).toBe(isCatchable(trip, NOW));
  });

  it('expiredTripFilter is the exact complement', () => {
    for (const trip of cases) {
      expect(matchesFilter(expiredTripFilter(NOW), trip)).toBe(!isCatchable(trip, NOW));
    }
  });
});
