import { BookingStatus, TripStatus } from '@prisma/client';
import { isBookingUpcoming, isRatableByRider } from './booking-lifecycle';

/**
 * The «قادمة» / «سابقة» rule.
 *
 * The bug this pins: a COMPLETED booking whose trip was SCHEDULED for later
 * stayed under «قادمة», because the bucket asked the clock instead of the
 * status. Every case below states which of the two it is testing.
 */
describe('isBookingUpcoming', () => {
  const NOW = new Date('2026-08-05T12:00:00Z');
  const LATER = new Date('2026-08-05T18:00:00Z'); // still in the future
  const EARLIER = new Date('2026-08-05T06:00:00Z'); // already passed

  const at = (
    bookingStatus: BookingStatus,
    tripStatus: TripStatus,
    departureTime: Date,
  ) => isBookingUpcoming({ bookingStatus, tripStatus, departureTime }, NOW);

  describe('a terminal BOOKING is past, whatever the clock says', () => {
    // The reported bug, exactly: driver completes a trip scheduled for tonight
    // and the rider still sees it under «قادمة».
    it.each([
      BookingStatus.COMPLETED,
      BookingStatus.CANCELLED,
      BookingStatus.NO_SHOW,
    ])('%s with a FUTURE departure is past', (status) => {
      expect(at(status, TripStatus.COMPLETED, LATER)).toBe(false);
    });

    it('COMPLETED with a future departure on a still-OPEN trip is past too', () => {
      // Defends the rule itself rather than one status pairing: the booking
      // being finished is sufficient on its own.
      expect(at(BookingStatus.COMPLETED, TripStatus.OPEN, LATER)).toBe(false);
    });
  });

  describe('a terminal TRIP is past, whatever the clock says', () => {
    it.each([TripStatus.COMPLETED, TripStatus.SETTLED, TripStatus.CANCELLED])(
      '%s with a FUTURE departure is past',
      (tripStatus) => {
        expect(at(BookingStatus.CONFIRMED, tripStatus, LATER)).toBe(false);
      },
    );

    it('a trip the driver cancelled for tomorrow is not something to wait for', () => {
      expect(at(BookingStatus.CONFIRMED, TripStatus.CANCELLED, LATER)).toBe(false);
    });
  });

  describe('a journey in progress is upcoming', () => {
    it('EN_ROUTE is upcoming even though departure has passed by definition', () => {
      expect(at(BookingStatus.CONFIRMED, TripStatus.EN_ROUTE, EARLIER)).toBe(true);
    });

    it('ONBOARD on an EN_ROUTE trip is upcoming', () => {
      expect(at(BookingStatus.ONBOARD, TripStatus.EN_ROUTE, EARLIER)).toBe(true);
    });
  });

  describe('otherwise the clock decides', () => {
    it.each([TripStatus.OPEN, TripStatus.LOCKED])(
      '%s in the future is upcoming',
      (tripStatus) => {
        expect(at(BookingStatus.CONFIRMED, tripStatus, LATER)).toBe(true);
      },
    );

    it.each([TripStatus.OPEN, TripStatus.LOCKED])(
      '%s already departed is past',
      (tripStatus) => {
        expect(at(BookingStatus.CONFIRMED, tripStatus, EARLIER)).toBe(false);
      },
    );
  });

  it('defaults `now` to the real clock', () => {
    const wayBack = new Date('2000-01-01T00:00:00Z');
    expect(
      isBookingUpcoming({
        bookingStatus: BookingStatus.CONFIRMED,
        tripStatus: TripStatus.OPEN,
        departureTime: wayBack,
      }),
    ).toBe(false);
  });
});

describe('isRatableByRider', () => {
  it('a COMPLETED booking on a finished trip is ratable', () => {
    expect(isRatableByRider(BookingStatus.COMPLETED, TripStatus.COMPLETED)).toBe(true);
    expect(isRatableByRider(BookingStatus.COMPLETED, TripStatus.SETTLED)).toBe(true);
  });

  it('a rider who never travelled cannot rate', () => {
    // Mirrors RatingService.assertSharedTrip, which requires a COMPLETED
    // booking. Offering an action the server refuses is worse than no action.
    expect(isRatableByRider(BookingStatus.NO_SHOW, TripStatus.COMPLETED)).toBe(false);
    expect(isRatableByRider(BookingStatus.CANCELLED, TripStatus.COMPLETED)).toBe(false);
  });

  it('cannot rate before the trip is finished', () => {
    expect(isRatableByRider(BookingStatus.CONFIRMED, TripStatus.EN_ROUTE)).toBe(false);
    expect(isRatableByRider(BookingStatus.ONBOARD, TripStatus.EN_ROUTE)).toBe(false);
    expect(isRatableByRider(BookingStatus.COMPLETED, TripStatus.EN_ROUTE)).toBe(false);
  });
});
