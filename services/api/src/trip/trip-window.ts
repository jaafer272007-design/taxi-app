import { Prisma } from '@prisma/client';

/**
 * When a trip stops being catchable by a rider.
 *
 * ## Why this file exists
 *
 * The rule used to be spelled out separately in three places — the search
 * query, the booking guard, and a comment about a future expiry job — and they
 * disagreed. `POST /trips` recorded a departNow trip as departing *now* and
 * documented a 30-minute validity window; `GET /trips/search` filtered to
 * `departureTime > now`. Each was defensible on its own, and together they made
 * every departNow trip invisible within a second of being posted.
 *
 * So the rule lives here once, in two forms that MUST agree: a predicate for a
 * trip already in hand, and the equivalent Prisma filter for the query that
 * fetches them. `trip-window.spec.ts` asserts they agree on the same fixtures,
 * because two encodings of one rule is exactly how the original bug happened.
 */

/**
 * How long a departNow trip stays live after it is posted.
 *
 * From the Phase 1 brief §4: «departNow=true → departureTime=now، ونافذة صلاحية
 * افتراضية 30 دقيقة». The driver is leaving imminently but wants riders to be
 * able to catch them for a while.
 */
export const DEPART_NOW_WINDOW_MINUTES = 30;

/** The fields the rule depends on — anything Trip-shaped will do. */
export interface TripWindowFields {
  departNow: boolean;
  departureTime: Date;
}

/** The instant a departNow trip stops accepting riders. */
export function departNowWindowEndsAt(departureTime: Date): Date {
  return new Date(departureTime.getTime() + DEPART_NOW_WINDOW_MINUTES * 60_000);
}

/**
 * The moment a trip stops being catchable.
 *
 * A **scheduled** trip is catchable until it departs — once the departure time
 * passes, it is gone, which is what a rider expects of a timetabled trip.
 *
 * A **departNow** trip departs immediately by definition, so the same test
 * would exclude it the instant it is created. It is catchable until its
 * validity window closes instead.
 */
export function catchableUntil(trip: TripWindowFields): Date {
  return trip.departNow ? departNowWindowEndsAt(trip.departureTime) : trip.departureTime;
}

/** Whether a rider can still find and book this trip. */
export function isCatchable(trip: TripWindowFields, now: Date = new Date()): boolean {
  return catchableUntil(trip).getTime() > now.getTime();
}

/** Milliseconds of window left, floored at zero. */
export function remainingWindowMs(trip: TripWindowFields, now: Date = new Date()): number {
  return Math.max(0, catchableUntil(trip).getTime() - now.getTime());
}

/**
 * {@link isCatchable} as a database filter.
 *
 * Expressed as an OR over the two kinds of trip rather than by widening the
 * bound for everything: a scheduled trip whose time has genuinely passed must
 * still disappear, and a blanket 30-minute grace period would resurrect it.
 */
export function catchableTripFilter(now: Date): Prisma.TripWhereInput {
  const windowFloor = new Date(now.getTime() - DEPART_NOW_WINDOW_MINUTES * 60_000);
  return {
    OR: [
      // Scheduled: unchanged — strictly in the future.
      { departNow: false, departureTime: { gt: now } },
      // departNow: posted within the last DEPART_NOW_WINDOW_MINUTES.
      { departNow: true, departureTime: { gt: windowFloor } },
    ],
  };
}

/** The complement — trips that are past it. Used by the expiry sweep. */
export function expiredTripFilter(now: Date): Prisma.TripWhereInput {
  const windowFloor = new Date(now.getTime() - DEPART_NOW_WINDOW_MINUTES * 60_000);
  return {
    OR: [
      { departNow: false, departureTime: { lte: now } },
      { departNow: true, departureTime: { lte: windowFloor } },
    ],
  };
}
