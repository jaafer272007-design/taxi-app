import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  BookingStatus,
  DriverProfile,
  DriverStatus,
  PaymentStatus,
  Trip,
  TripCreatedBy,
  TripStatus,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
import { NotificationService, NotificationPayload } from '../notification/notification.service';
import { CreateTripDto } from './dto/create-trip.dto';
import { UpdateTripDto } from './dto/update-trip.dto';

/**
 * A departNow trip departs immediately and is meant to stay valid for this
 * window. It is derived from departureTime (= now) — no separate column.
 * TODO(Step 4/5): a background job should LOCK/expire departNow trips once the
 * window passes; that only matters once bookings exist.
 */
const DEPART_NOW_WINDOW_MINUTES = 30;

@Injectable()
export class TripService {
  private readonly logger = new Logger(TripService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriverService,
    private readonly corridors: CorridorService,
    private readonly notifications: NotificationService,
  ) {}

  /** Driver posts a trip. Only an APPROVED driver may create one. */
  async createTrip(userId: string, dto: CreateTripDto): Promise<Trip> {
    // Gate: throws 403 if the driver is not APPROVED (or 400 if not a driver yet).
    const profile = await this.drivers.assertApprovedDriver(userId);

    const vehicle = await this.prisma.vehicle.findUnique({ where: { driverId: profile.id } });
    if (!vehicle) {
      throw new BadRequestException('أضف مركبة قبل إعلان رحلة.');
    }
    if (dto.seatsTotal > vehicle.seats) {
      throw new BadRequestException(
        `عدد المقاعد (${dto.seatsTotal}) يتجاوز سعة سيارتك (${vehicle.seats}).`,
      );
    }

    const corridor = await this.corridors.findById(dto.corridorId);
    if (!corridor) {
      throw new NotFoundException('الممر غير موجود.');
    }
    if (!corridor.active) {
      throw new BadRequestException('هذا الممر غير مفعّل حالياً.');
    }

    // Enforce the DTO's EITHER/OR contract: don't silently discard a scheduled
    // time when departNow is also set.
    if (dto.departNow === true && dto.departureTime !== undefined) {
      throw new BadRequestException('حدّد وقت المغادرة أو فعّل "الآن"، وليس الاثنين معاً.');
    }

    const departNow = dto.departNow === true;
    const departureTime = departNow ? new Date() : this.parseFutureDate(dto.departureTime);

    if (departNow) {
      // Derived validity window (not persisted). The expiry job in Step 4/5 will
      // enforce it once bookings exist.
      const windowEndsAt = new Date(departureTime.getTime() + DEPART_NOW_WINDOW_MINUTES * 60_000);
      this.logger.debug(`departNow trip window ends ~${windowEndsAt.toISOString()}`);
    }

    return this.prisma.trip.create({
      data: {
        corridorId: corridor.id,
        driverId: profile.id,
        vehicleId: vehicle.id,
        departureTime,
        departNow,
        seatsTotal: dto.seatsTotal,
        seatsAvailable: dto.seatsTotal,
        pricePerSeat: corridor.pricePerSeat, // snapshot from the corridor
        status: TripStatus.OPEN,
        createdBy: TripCreatedBy.DRIVER,
      },
    });
  }

  /** The current driver's trips. Empty list if the user is not a driver. */
  async listMine(userId: string): Promise<Trip[]> {
    const profile = await this.drivers.findProfileByUserId(userId);
    if (!profile) {
      return [];
    }
    return this.prisma.trip.findMany({
      where: { driverId: profile.id },
      orderBy: { departureTime: 'desc' },
    });
  }

  /** Edit a trip — allowed only while it is OPEN, by the owning driver. */
  async updateTrip(userId: string, tripId: string, dto: UpdateTripDto): Promise<Trip> {
    const { trip, profile } = await this.getOwnedTrip(userId, tripId);
    if (trip.status !== TripStatus.OPEN) {
      throw new ConflictException('لا يمكن تعديل الرحلة إلا وهي مفتوحة (OPEN).');
    }

    const data: { seatsTotal?: number; seatsAvailable?: number; departureTime?: Date } = {};

    if (dto.seatsTotal !== undefined) {
      const vehicle = await this.prisma.vehicle.findUnique({ where: { driverId: profile.id } });
      if (!vehicle) {
        throw new BadRequestException('لا توجد مركبة.');
      }
      if (dto.seatsTotal > vehicle.seats) {
        throw new BadRequestException(
          `عدد المقاعد (${dto.seatsTotal}) يتجاوز سعة سيارتك (${vehicle.seats}).`,
        );
      }
      // Can't shrink total capacity below seats already booked.
      const booked = trip.seatsTotal - trip.seatsAvailable;
      if (dto.seatsTotal < booked) {
        throw new BadRequestException(`لا يمكن تقليل المقاعد تحت عدد المحجوز (${booked}).`);
      }
      data.seatsTotal = dto.seatsTotal;
      data.seatsAvailable = dto.seatsTotal - booked;
    }

    if (dto.departureTime !== undefined) {
      data.departureTime = this.parseFutureDate(dto.departureTime);
    }

    return this.prisma.trip.update({ where: { id: tripId }, data });
  }

  /** Cancel a trip. Allowed any time before EN_ROUTE, by the owning driver. */
  async cancelTrip(userId: string, tripId: string): Promise<Trip> {
    const { trip } = await this.getOwnedTrip(userId, tripId);
    if (trip.status !== TripStatus.OPEN && trip.status !== TripStatus.LOCKED) {
      throw new ConflictException('لا يمكن إلغاء الرحلة بحالتها الحالية.');
    }

    // Riders to notify (captured before cancelling).
    const affected = await this.prisma.seatBooking.findMany({
      where: { tripId, status: BookingStatus.CONFIRMED },
      select: { riderId: true },
    });

    // Cancelling a trip cancels its confirmed bookings too (brief §6).
    const cancelled = await this.prisma.$transaction(async (tx) => {
      await tx.seatBooking.updateMany({
        where: { tripId, status: BookingStatus.CONFIRMED },
        data: { status: BookingStatus.CANCELLED },
      });
      return tx.trip.update({ where: { id: tripId }, data: { status: TripStatus.CANCELLED } });
    });

    // AFTER commit: notify the riders whose bookings were cancelled.
    await this.notifyRiders(affected, {
      title: 'إلغاء الرحلة',
      body: 'أُلغيت الرحلة من قبل السائق.',
      data: { type: 'trip.cancelled', tripId },
    });
    return cancelled;
  }

  /** Push a notification to each distinct rider (after commit). */
  private async notifyRiders(
    rows: Array<{ riderId: string }>,
    payload: NotificationPayload,
  ): Promise<void> {
    const riderIds = [...new Set(rows.map((r) => r.riderId))];
    await Promise.all(riderIds.map((id) => this.notifications.send(id, payload)));
  }

  /** Start the trip: OPEN|LOCKED → EN_ROUTE (owning APPROVED driver only). */
  async start(userId: string, tripId: string): Promise<Trip> {
    const { trip, profile } = await this.getOwnedTrip(userId, tripId);
    if (profile.status !== DriverStatus.APPROVED) {
      throw new ForbiddenException('يجب أن يكون حسابك معتمداً.');
    }
    if (trip.status !== TripStatus.OPEN && trip.status !== TripStatus.LOCKED) {
      throw new ConflictException('لا يمكن بدء الرحلة بحالتها الحالية.');
    }
    // From EN_ROUTE on: booking is blocked (status != OPEN) and rider self-cancel
    // is blocked (booking.cancel rejects EN_ROUTE/COMPLETED trips).
    const updated = await this.prisma.trip.update({
      where: { id: tripId },
      data: { status: TripStatus.EN_ROUTE },
    });

    const riders = await this.prisma.seatBooking.findMany({
      where: { tripId, status: BookingStatus.CONFIRMED },
      select: { riderId: true },
    });
    await this.notifyRiders(riders, {
      title: 'انطلقت الرحلة',
      body: 'انطلقت رحلتك.',
      data: { type: 'trip.started', tripId },
    });
    return updated;
  }

  /**
   * Complete the trip (owning driver, EN_ROUTE only). In ONE transaction:
   * settle every riding booking to COMPLETED + COLLECTED (cash), record one
   * EarningsRecord for the collected sum, bump tripsDone, and move the trip
   * EN_ROUTE → COMPLETED → SETTLED.
   *
   * Settlement policy (documented): ONBOARD and still-CONFIRMED bookings both
   * default to "rode" → COMPLETED + COLLECTED (keeps cash accounting simple).
   * NO_SHOW stays NO_SHOW / PENDING and is excluded from earnings. CANCELLED is
   * left untouched.
   */
  async complete(userId: string, tripId: string): Promise<Trip> {
    const { trip, profile } = await this.getOwnedTrip(userId, tripId);
    if (trip.status !== TripStatus.EN_ROUTE) {
      throw new ConflictException('لا يمكن إكمال الرحلة إلا وهي جارية (EN_ROUTE).');
    }

    const settled = await this.prisma.$transaction(async (tx) => {
      const bookings = await tx.seatBooking.findMany({ where: { tripId } });

      let collected = 0;
      for (const b of bookings) {
        if (b.status === BookingStatus.ONBOARD || b.status === BookingStatus.CONFIRMED) {
          await tx.seatBooking.update({
            where: { id: b.id },
            data: { status: BookingStatus.COMPLETED, paymentStatus: PaymentStatus.COLLECTED },
          });
          collected += b.fare;
        }
        // NO_SHOW (excluded, stays PENDING) and CANCELLED are left untouched.
      }

      await tx.trip.update({ where: { id: tripId }, data: { status: TripStatus.COMPLETED } });

      if (collected > 0) {
        await tx.earningsRecord.create({ data: { driverId: profile.id, tripId, amount: collected } });
      }
      await tx.driverProfile.update({
        where: { id: profile.id },
        data: { tripsDone: { increment: 1 } },
      });

      return tx.trip.update({ where: { id: tripId }, data: { status: TripStatus.SETTLED } });
    });

    // AFTER commit: notify riders who completed the trip so they can rate.
    const riders = await this.prisma.seatBooking.findMany({
      where: { tripId, status: BookingStatus.COMPLETED },
      select: { riderId: true },
    });
    await this.notifyRiders(riders, {
      title: 'اكتملت الرحلة',
      body: 'اكتملت رحلتك، قيّم سائقك.',
      data: { type: 'trip.completed', tripId },
    });
    return settled;
  }

  private async getOwnedTrip(
    userId: string,
    tripId: string,
  ): Promise<{ trip: Trip; profile: DriverProfile }> {
    const profile = await this.drivers.findProfileByUserId(userId);
    if (!profile) {
      throw new ForbiddenException('لست سائقاً.');
    }
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) {
      throw new NotFoundException('الرحلة غير موجودة.');
    }
    if (trip.driverId !== profile.id) {
      throw new ForbiddenException('هذه ليست رحلتك.');
    }
    return { trip, profile };
  }

  private parseFutureDate(value?: string): Date {
    if (!value) {
      throw new BadRequestException('حدّد وقت المغادرة أو فعّل "الآن" (departNow).');
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime()) || date.getTime() <= Date.now()) {
      throw new BadRequestException('وقت المغادرة يجب أن يكون في المستقبل.');
    }
    return date;
  }
}
