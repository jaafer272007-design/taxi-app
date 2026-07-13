import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { DriverProfile, Trip, TripCreatedBy, TripStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { CorridorService } from '../corridor/corridor.service';
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
    return this.prisma.trip.update({
      where: { id: tripId },
      data: { status: TripStatus.CANCELLED },
    });
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
