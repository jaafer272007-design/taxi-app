import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  BookingStatus,
  PaymentMethod,
  PaymentStatus,
  Prisma,
  SeatBooking,
  TripStatus,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { SearchTripsDto } from './dto/search-trips.dto';

const CANCEL_CUTOFF_MINUTES = 15;

@Injectable()
export class BookingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriverService,
  ) {}

  /** Rider-facing search: only OPEN, future, seats-available trips. */
  async search(dto: SearchTripsDto) {
    const now = new Date();
    const departureTime: Prisma.DateTimeFilter[] = [{ gt: now }];

    if (dto.date) {
      const day = dto.date.slice(0, 10); // YYYY-MM-DD
      const dayStart = new Date(`${day}T00:00:00`); // process TZ = Asia/Baghdad
      const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
      departureTime.push({ gte: dayStart, lt: dayEnd });
    }
    if (dto.fromTime) departureTime.push({ gte: new Date(dto.fromTime) });
    if (dto.toTime) departureTime.push({ lte: new Date(dto.toTime) });

    const where: Prisma.TripWhereInput = {
      status: TripStatus.OPEN,
      seatsAvailable: { gt: 0 },
      AND: departureTime.map((filter) => ({ departureTime: filter })),
    };
    if (dto.corridorId) where.corridorId = dto.corridorId;

    const trips = await this.prisma.trip.findMany({ where, orderBy: { departureTime: 'asc' } });
    if (trips.length === 0) return [];

    // Trip.driverId / vehicleId are plain FKs (no Prisma relation), so enrich in bulk.
    const driverIds = [...new Set(trips.map((t) => t.driverId))];
    const vehicleIds = [...new Set(trips.map((t) => t.vehicleId))];
    const [drivers, vehicles] = await Promise.all([
      this.prisma.driverProfile.findMany({
        where: { id: { in: driverIds } },
        select: { id: true, ratingAvg: true },
      }),
      this.prisma.vehicle.findMany({
        where: { id: { in: vehicleIds } },
        select: { id: true, make: true, model: true, color: true, seats: true },
      }),
    ]);
    const driverMap = new Map(drivers.map((d) => [d.id, d]));
    const vehicleMap = new Map(vehicles.map((v) => [v.id, v]));

    return trips.map((t) => {
      const vehicle = vehicleMap.get(t.vehicleId);
      return {
        id: t.id,
        corridorId: t.corridorId,
        departureTime: t.departureTime,
        pricePerSeat: t.pricePerSeat,
        seatsAvailable: t.seatsAvailable,
        driverRatingAvg: driverMap.get(t.driverId)?.ratingAvg ?? 0,
        vehicle: vehicle
          ? { make: vehicle.make, model: vehicle.model, color: vehicle.color, seats: vehicle.seats }
          : null,
      };
    });
  }

  /** Book seats on a trip. Seat reservation is atomic and overbooking-safe. */
  async book(userId: string, dto: CreateBookingDto): Promise<SeatBooking> {
    const trip = await this.prisma.trip.findUnique({ where: { id: dto.tripId } });
    if (!trip) {
      throw new NotFoundException('الرحلة غير موجودة.');
    }
    if (trip.status !== TripStatus.OPEN) {
      throw new ConflictException('الرحلة غير متاحة للحجز.');
    }
    if (trip.departureTime.getTime() <= Date.now()) {
      throw new ConflictException('انتهى وقت هذه الرحلة.');
    }
    const myProfile = await this.drivers.findProfileByUserId(userId);
    if (myProfile && myProfile.id === trip.driverId) {
      throw new BadRequestException('لا يمكنك حجز رحلتك الخاصة.');
    }
    if (dto.seatCount > trip.seatsAvailable) {
      throw new ConflictException('المقاعد المطلوبة غير متاحة.');
    }

    return this.prisma.$transaction(async (tx) => {
      // Atomic, race-safe reservation. The WHERE guard (status OPEN AND
      // seatsAvailable >= seatCount) makes concurrent bookings for the last
      // seat safe: exactly one UPDATE affects the row; the loser sees count 0.
      // seatsAvailable can never go negative.
      const reserved = await tx.trip.updateMany({
        where: { id: dto.tripId, status: TripStatus.OPEN, seatsAvailable: { gte: dto.seatCount } },
        data: { seatsAvailable: { decrement: dto.seatCount } },
      });
      if (reserved.count !== 1) {
        throw new ConflictException('لم يعد المقعد متاحاً.');
      }

      const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: dto.tripId } });
      // Auto-lock the trip when it fills up (business rule: lock at seatsAvailable=0).
      if (afterTrip.seatsAvailable === 0) {
        await tx.trip.update({ where: { id: dto.tripId }, data: { status: TripStatus.LOCKED } });
      }

      // TODO(Step 6): emit "booking.created" to notify the driver.
      // TODO(Phase 2): validate pickup within origin city / dropoff within dest city (PostGIS).
      return tx.seatBooking.create({
        data: {
          tripId: dto.tripId,
          riderId: userId,
          pickupLat: dto.pickup.lat,
          pickupLng: dto.pickup.lng,
          pickupLabel: dto.pickup.label,
          dropoffLat: dto.dropoff.lat,
          dropoffLng: dto.dropoff.lng,
          dropoffLabel: dto.dropoff.label,
          seatCount: dto.seatCount,
          fare: afterTrip.pricePerSeat * dto.seatCount,
          paymentMethod: PaymentMethod.CASH,
          paymentStatus: PaymentStatus.PENDING,
          status: BookingStatus.CONFIRMED,
        },
      });
    });
  }

  /** Rider's bookings with trip info; each flagged upcoming vs past. */
  async listMine(userId: string) {
    const bookings = await this.prisma.seatBooking.findMany({
      where: { riderId: userId },
      include: { trip: { include: { corridor: true } } },
      orderBy: { createdAt: 'desc' },
    });
    const now = Date.now();
    return bookings.map((b) => ({ ...b, upcoming: b.trip.departureTime.getTime() > now }));
  }

  /** Cancel a booking (owning rider), returning the seat atomically. */
  async cancel(userId: string, bookingId: string): Promise<SeatBooking> {
    const booking = await this.prisma.seatBooking.findUnique({
      where: { id: bookingId },
      include: { trip: true },
    });
    if (!booking) {
      throw new NotFoundException('الحجز غير موجود.');
    }
    if (booking.riderId !== userId) {
      throw new ForbiddenException('هذا ليس حجزك.');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new ConflictException('لا يمكن إلغاء هذا الحجز.');
    }
    const trip = booking.trip;
    if (trip.status === TripStatus.EN_ROUTE || trip.status === TripStatus.COMPLETED) {
      throw new ConflictException('لا يمكن الإلغاء بعد بدء الرحلة.');
    }
    const cutoffMs = trip.departureTime.getTime() - CANCEL_CUTOFF_MINUTES * 60 * 1000;
    if (Date.now() >= cutoffMs) {
      throw new ConflictException('فات وقت الإلغاء المجاني (قبل 15 دقيقة من المغادرة).');
    }

    return this.prisma.$transaction(async (tx) => {
      // Race guard: only one concurrent cancel flips CONFIRMED→CANCELLED, so the
      // seat is returned exactly once (no double refund).
      const cancelled = await tx.seatBooking.updateMany({
        where: { id: bookingId, status: BookingStatus.CONFIRMED },
        data: { status: BookingStatus.CANCELLED },
      });
      if (cancelled.count !== 1) {
        throw new ConflictException('تم إلغاء الحجز مسبقاً.');
      }

      await tx.trip.update({
        where: { id: trip.id },
        data: { seatsAvailable: { increment: booking.seatCount } },
      });

      // Reopen a full-but-not-departed trip so freed seats are bookable again.
      const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: trip.id } });
      if (afterTrip.status === TripStatus.LOCKED && afterTrip.departureTime.getTime() > Date.now()) {
        await tx.trip.update({ where: { id: trip.id }, data: { status: TripStatus.OPEN } });
      }

      return tx.seatBooking.findUniqueOrThrow({ where: { id: bookingId } });
    });
  }

  /** Driver marks a rider onboard: CONFIRMED → ONBOARD (trip must be EN_ROUTE). */
  onboard(userId: string, bookingId: string): Promise<SeatBooking> {
    return this.driverBookingTransition(userId, bookingId, BookingStatus.ONBOARD);
  }

  /**
   * Driver marks a rider no-show: CONFIRMED → NO_SHOW (trip must be EN_ROUTE).
   * The seat is NOT returned (held; no cash refund in the MVP) and the fare is
   * excluded from earnings at completion. Recorded for rider reputation.
   */
  noShow(userId: string, bookingId: string): Promise<SeatBooking> {
    return this.driverBookingTransition(userId, bookingId, BookingStatus.NO_SHOW);
  }

  private async driverBookingTransition(
    userId: string,
    bookingId: string,
    target: BookingStatus,
  ): Promise<SeatBooking> {
    const booking = await this.prisma.seatBooking.findUnique({
      where: { id: bookingId },
      include: { trip: true },
    });
    if (!booking) {
      throw new NotFoundException('الحجز غير موجود.');
    }
    const profile = await this.drivers.findProfileByUserId(userId);
    if (!profile || profile.id !== booking.trip.driverId) {
      throw new ForbiddenException('هذه ليست رحلتك.');
    }
    if (booking.trip.status !== TripStatus.EN_ROUTE) {
      throw new ConflictException('يجب أن تكون الرحلة جارية (EN_ROUTE).');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new ConflictException('لا يمكن تغيير حالة هذا الحجز.');
    }
    return this.prisma.seatBooking.update({ where: { id: bookingId }, data: { status: target } });
  }
}
