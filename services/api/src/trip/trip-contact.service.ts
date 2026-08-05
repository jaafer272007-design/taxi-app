import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';

/** Which side of the trip the CALLER is on. */
export type ContactRole = 'DRIVER' | 'RIDER';

/** One reachable person, with the booking that makes them reachable. */
export interface TripContact {
  userId: string;
  name: string | null;

  /** Canonical E.164, e.g. `+9647701234567`. */
  phone: string;

  /**
   * The booking that connects the caller to this contact — the rider's booking
   * in BOTH directions. For a driver it says which of their bookings this
   * rider is; for a rider it is their own booking, the thing that entitles
   * them to the driver's number in the first place.
   */
  bookingId: string;
}

export interface TripContacts {
  role: ContactRole;
  contacts: TripContact[];
}

/**
 * Phone numbers between a driver and their riders.
 *
 * ─── THE ONLY PLACE A PHONE NUMBER LEAVES THE SERVER ──────────────────────
 * No other endpoint returns one — not trip search, not the trip list, not the
 * bookings list. That is deliberate and it is the whole security design: the
 * rule "you may see the other party's number once a booking exists between
 * you" is expensive to state and cheap to get subtly wrong, so it is stated
 * ONCE, here, and every screen that shows a number goes through this service.
 *
 * A second copy of an access rule is the same failure mode that made every
 * departNow trip invisible (see trip-window.ts) — except that one only cost
 * visibility, and this one would cost every driver's phone number.
 * ──────────────────────────────────────────────────────────────────────────
 *
 * Entitlement, in full:
 *
 * | caller                                    | gets                        |
 * |-------------------------------------------|-----------------------------|
 * | the trip's own driver                     | every non-cancelled rider   |
 * | a rider with a non-cancelled booking on it| the driver, once            |
 * | anyone else (incl. a CANCELLED booking)   | **403**                     |
 *
 * A cancelled booking is not a relationship. The seat was returned, the fare
 * is void, and the two of them have no reason to reach each other — so the
 * number goes away with the booking. NO_SHOW and COMPLETED do NOT: the ride
 * happened (or was meant to), and a forgotten bag is a real phone call.
 */
@Injectable()
export class TripContactService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriverService,
  ) {}

  /** Bookings that count as a live relationship between a rider and a trip. */
  private static readonly ACTIVE_BOOKING = { not: BookingStatus.CANCELLED } as const;

  async listContacts(userId: string, tripId: string): Promise<TripContacts> {
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      select: { id: true, driverId: true },
    });
    if (!trip) {
      throw new NotFoundException('الرحلة غير موجودة.');
    }

    const profile = await this.drivers.findProfileByUserId(userId);
    if (profile && profile.id === trip.driverId) {
      return { role: 'DRIVER', contacts: await this.ridersOf(trip.id) };
    }

    // Not the driver → the only other way in is an active booking of your own.
    const booking = await this.prisma.seatBooking.findFirst({
      where: {
        tripId: trip.id,
        riderId: userId,
        status: TripContactService.ACTIVE_BOOKING,
      },
      select: { id: true },
      orderBy: { createdAt: 'asc' },
    });
    if (!booking) {
      throw new ForbiddenException('لا يمكنك الاطلاع على بيانات التواصل لهذه الرحلة.');
    }

    return {
      role: 'RIDER',
      contacts: await this.driverOf(trip.driverId, booking.id),
    };
  }

  /** Every rider holding a live booking on this trip. */
  private async ridersOf(tripId: string): Promise<TripContact[]> {
    const bookings = await this.prisma.seatBooking.findMany({
      where: { tripId, status: TripContactService.ACTIVE_BOOKING },
      select: { id: true, riderId: true },
      orderBy: { createdAt: 'asc' },
    });
    if (bookings.length === 0) {
      return [];
    }

    // SeatBooking.riderId is a plain scalar (no Prisma relation), so join in bulk
    // the same way trip search does.
    const riderIds = [...new Set(bookings.map((b) => b.riderId))];
    const riders = await this.prisma.user.findMany({
      where: { id: { in: riderIds } },
      select: { id: true, name: true, phone: true },
    });
    const byId = new Map(riders.map((r) => [r.id, r]));

    const out: TripContact[] = [];
    for (const b of bookings) {
      const rider = byId.get(b.riderId);
      // A booking whose user row vanished has no number to give; drop the row
      // rather than emit a contact with an empty phone the UI would render as
      // a dead "call" button.
      if (!rider) continue;
      out.push({
        userId: rider.id,
        name: rider.name,
        phone: rider.phone,
        bookingId: b.id,
      });
    }
    return out;
  }

  /** The trip's driver, as the single contact a rider is entitled to. */
  private async driverOf(driverProfileId: string, bookingId: string): Promise<TripContact[]> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { id: driverProfileId },
      select: { user: { select: { id: true, name: true, phone: true } } },
    });
    const user = profile?.user;
    if (!user) {
      return [];
    }
    return [{ userId: user.id, name: user.name, phone: user.phone, bookingId }];
  }
}
