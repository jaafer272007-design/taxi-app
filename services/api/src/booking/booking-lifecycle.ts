import { BookingStatus, TripStatus } from '@prisma/client';
import { catchableUntil, TripWindowFields } from '../trip/trip-window';

/**
 * Where a booking belongs in حجوزاتي — «قادمة» (upcoming) or «سابقة» (past).
 *
 * ─── WHY THIS IS A STATUS QUESTION, NOT A CLOCK QUESTION ───────────────────
 *
 * This used to be `departureTime > now`, nothing else. A driver would complete
 * a trip and the rider's booking — badge reading «مكتملة» — stayed filed under
 * «قادمة», because the trip had been *scheduled* for later that day. Every
 * layer was individually right; the bucket just asked the wrong question.
 *
 * It is the same confusion that made departNow trips invisible: **when it was
 * scheduled vs what state it is in**. So, like `trip-window.ts`, the rule lives
 * in exactly one place and every caller uses it.
 *
 * «قادمة» holds only what is still ACTIONABLE:
 *
 *  1. A **terminal booking** is past — COMPLETED, CANCELLED, NO_SHOW. Nothing
 *     can happen to it again, whatever the clock says.
 *  2. A **terminal trip** is past — COMPLETED, SETTLED, CANCELLED. A cancelled
 *     trip scheduled for tomorrow is not something the rider is waiting for.
 *  3. An **EN_ROUTE trip is upcoming**, even though its departure time has
 *     passed by definition. A journey in progress is the one thing that is
 *     most certainly not in the past — filing it there was the old rule's
 *     other half of the same mistake.
 *  4. Otherwise (OPEN or LOCKED, booking still live) the trip is upcoming for
 *     as long as it is still LIVE — and "live" is `catchableUntil`, never a
 *     raw `departureTime > now`.
 *
 * ─── WHY STEP 4 MUST NOT SPELL THE CLOCK OUT ITSELF ────────────────────────
 *
 * It used to read `departureTime.getTime() > now.getTime()`, and that is the
 * single expression `trip-window.ts` exists to stamp out. **A departNow trip
 * has `departureTime === now` by definition**, so the test was false the
 * instant such a trip was posted: a rider could book a trip that search was
 * still offering them, and the booking landed in «سابقة» before the tap
 * finished. From there `canCancel` (which requires `upcoming`) drew no cancel
 * button, `hasLiveBookings` was false so حجوزاتي stopped polling, and the seats
 * were held with no way for the rider to release them.
 *
 * That is the third time this exact expression has caused a bug — search and
 * the booking guard were the first two, which is why `trip-window.ts` was
 * written. Do not re-derive it here. Ask `catchableUntil`.
 */
export const TERMINAL_BOOKING_STATUSES: readonly BookingStatus[] = [
  BookingStatus.COMPLETED,
  BookingStatus.CANCELLED,
  BookingStatus.NO_SHOW,
];

export const TERMINAL_TRIP_STATUSES: readonly TripStatus[] = [
  TripStatus.COMPLETED,
  TripStatus.SETTLED,
  TripStatus.CANCELLED,
];

export function isTerminalBookingStatus(status: BookingStatus): boolean {
  return TERMINAL_BOOKING_STATUSES.includes(status);
}

export function isTerminalTripStatus(status: TripStatus): boolean {
  return TERMINAL_TRIP_STATUSES.includes(status);
}

/**
 * Everything the bucket depends on. [departNow] is not optional and not a
 * detail: without it there is no way to tell "leaving now" from "already gone",
 * and assuming the latter is precisely the bug documented above.
 */
export interface BookingBucketInput extends TripWindowFields {
  bookingStatus: BookingStatus;
  tripStatus: TripStatus;
}

/** True when the booking still belongs under «قادمة». See the doc above. */
export function isBookingUpcoming(
  { bookingStatus, tripStatus, departNow, departureTime }: BookingBucketInput,
  now: Date = new Date(),
): boolean {
  if (isTerminalBookingStatus(bookingStatus)) return false;
  if (isTerminalTripStatus(tripStatus)) return false;
  if (tripStatus === TripStatus.EN_ROUTE) return true;
  return catchableUntil({ departNow, departureTime }).getTime() > now.getTime();
}

/**
 * Whether this booking has reached the point where the rider may rate their
 * driver: the ride actually happened.
 *
 * COMPLETED only — a NO_SHOW rider never travelled, and the backend's
 * `RatingService.assertSharedTrip` refuses them for the same reason. Keeping
 * the two in step matters: an action the UI offers and the server rejects is
 * worse than no action at all.
 */
export function isRatableByRider(
  bookingStatus: BookingStatus,
  tripStatus: TripStatus,
): boolean {
  return (
    bookingStatus === BookingStatus.COMPLETED &&
    (tripStatus === TripStatus.COMPLETED || tripStatus === TripStatus.SETTLED)
  );
}
