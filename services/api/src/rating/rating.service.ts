import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { BookingStatus, Rating, TripStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateRatingDto } from './dto/create-rating.dto';

@Injectable()
export class RatingService {
  constructor(private readonly prisma: PrismaService) {}

  /** Rate a co-traveller after the trip completed. One rating per (trip, from, to). */
  async create(fromUserId: string, dto: CreateRatingDto): Promise<Rating> {
    if (dto.toUserId === fromUserId) {
      throw new BadRequestException('لا يمكنك تقييم نفسك.');
    }

    const trip = await this.prisma.trip.findUnique({ where: { id: dto.tripId } });
    if (!trip) {
      throw new NotFoundException('الرحلة غير موجودة.');
    }
    if (trip.status !== TripStatus.COMPLETED && trip.status !== TripStatus.SETTLED) {
      throw new ConflictException('لا يمكن التقييم إلا بعد اكتمال الرحلة.');
    }

    await this.assertSharedTrip(trip.id, trip.driverId, fromUserId, dto.toUserId);

    const existing = await this.prisma.rating.findFirst({
      where: { tripId: dto.tripId, fromUserId, toUserId: dto.toUserId },
    });
    if (existing) {
      throw new ConflictException('قيّمت هذا الشخص مسبقاً لهذه الرحلة.');
    }

    const rating = await this.prisma.rating.create({
      data: {
        tripId: dto.tripId,
        fromUserId,
        toUserId: dto.toUserId,
        score: dto.score,
        comment: dto.comment ?? null,
      },
    });

    await this.recomputeAvg(dto.toUserId);
    return rating;
  }

  /** Aggregate rating + recent comments for any user (driver or rider). */
  async getUserRatings(userId: string) {
    const agg = await this.prisma.rating.aggregate({
      where: { toUserId: userId },
      _avg: { score: true },
      _count: true,
    });
    const recent = await this.prisma.rating.findMany({
      where: { toUserId: userId },
      orderBy: { createdAt: 'desc' },
      take: 10,
      select: { score: true, comment: true, tripId: true, fromUserId: true, createdAt: true },
    });
    return { userId, ratingAvg: agg._avg.score ?? 0, ratingCount: agg._count, recent };
  }

  /**
   * Both parties must have shared this trip: one is the driver, the other is a
   * rider with a COMPLETED booking on it. Works in either rating direction.
   */
  private async assertSharedTrip(
    tripId: string,
    tripDriverProfileId: string,
    fromUserId: string,
    toUserId: string,
  ): Promise<void> {
    const driverProfile = await this.prisma.driverProfile.findUnique({
      where: { id: tripDriverProfileId },
      select: { userId: true },
    });
    const driverUserId = driverProfile?.userId;
    if (!driverUserId || (driverUserId !== fromUserId && driverUserId !== toUserId)) {
      throw new ForbiddenException('لا يمكنك تقييم شخص لم تشاركه هذه الرحلة.');
    }

    const riderUserId = fromUserId === driverUserId ? toUserId : fromUserId;
    const riderBooking = await this.prisma.seatBooking.findFirst({
      where: { tripId, riderId: riderUserId, status: BookingStatus.COMPLETED },
    });
    if (!riderBooking) {
      throw new ForbiddenException('لا يمكنك تقييم شخص لم تشاركه هذه الرحلة.');
    }
  }

  /**
   * Recompute the target's average. Drivers keep it denormalized on
   * DriverProfile.ratingAvg (used by trip search); rider averages are computed
   * on read in getUserRatings.
   */
  private async recomputeAvg(userId: string): Promise<void> {
    const agg = await this.prisma.rating.aggregate({
      where: { toUserId: userId },
      _avg: { score: true },
    });
    const avg = agg._avg.score ?? 0;

    const profile = await this.prisma.driverProfile.findUnique({ where: { userId } });
    if (profile) {
      await this.prisma.driverProfile.update({ where: { id: profile.id }, data: { ratingAvg: avg } });
    }
  }
}
