import { Injectable, NotFoundException } from '@nestjs/common';
import { DriverStatus, Prisma, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationService } from '../notification/notification.service';
import { ListTripsDto } from './dto/list-trips.dto';

const DRIVER_INCLUDE = {
  user: { select: { id: true, phone: true, name: true, roles: true, createdAt: true } },
  vehicle: true,
  documents: true,
} as const;

interface StatusChange {
  status: DriverStatus;
  rejectionReason?: string | null;
}

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationService,
  ) {}

  /** List drivers (optionally filtered by status) with their vehicle + documents. */
  listDrivers(status?: DriverStatus) {
    return this.prisma.driverProfile.findMany({
      where: status ? { status } : {},
      include: DRIVER_INCLUDE,
    });
  }

  async approve(id: string) {
    const profile = await this.setStatus(id, { status: DriverStatus.APPROVED, rejectionReason: null });
    await this.notifications.send(profile.user.id, {
      title: 'تم الاعتماد',
      body: 'تم اعتماد حسابك كسائق. يمكنك الآن إعلان الرحلات.',
      data: { type: 'driver.approved' },
    });
    return profile;
  }

  async reject(id: string, reason?: string) {
    const profile = await this.setStatus(id, {
      status: DriverStatus.REJECTED,
      rejectionReason: reason ?? null,
    });
    await this.notifications.send(profile.user.id, {
      title: 'تم رفض الطلب',
      body: reason ? `تم رفض طلبك: ${reason}` : 'تم رفض طلبك.',
      data: { type: 'driver.rejected' },
    });
    return profile;
  }

  suspend(id: string) {
    // Suspension is not a rejection — leave rejectionReason untouched, no push.
    return this.setStatus(id, { status: DriverStatus.SUSPENDED });
  }

  /** Aggregate counts for the admin dashboard. Kept to a handful of queries. */
  async getDashboard() {
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startOfTomorrow = new Date(startOfToday.getTime() + 24 * 60 * 60 * 1000);

    const [totalRiders, driverGroups, tripGroups, totalBookings, earningsAgg, tripsToday] =
      await Promise.all([
        this.prisma.user.count({ where: { roles: { has: UserRole.RIDER } } }),
        this.prisma.driverProfile.groupBy({ by: ['status'], _count: { _all: true } }),
        this.prisma.trip.groupBy({ by: ['status'], _count: { _all: true } }),
        this.prisma.seatBooking.count(),
        this.prisma.earningsRecord.aggregate({ _sum: { amount: true } }),
        this.prisma.trip.count({
          where: { departureTime: { gte: startOfToday, lt: startOfTomorrow } },
        }),
      ]);

    const driversByStatus = this.toCountMap(driverGroups);
    const tripsByStatus = this.toCountMap(tripGroups);

    return {
      riders: totalRiders,
      drivers: { total: sum(driversByStatus), byStatus: driversByStatus },
      trips: { total: sum(tripsByStatus), byStatus: tripsByStatus, today: tripsToday },
      bookings: totalBookings,
      earningsTotal: earningsAgg._sum.amount ?? 0,
    };
  }

  /** Paginated trips monitor with driver info + booking counts. */
  async listTrips(dto: ListTripsDto) {
    const page = dto.page && dto.page > 0 ? dto.page : 1;
    const perPage = dto.perPage && dto.perPage > 0 ? Math.min(dto.perPage, 100) : 20;

    const where: Prisma.TripWhereInput = {};
    if (dto.status) where.status = dto.status;
    if (dto.corridorId) where.corridorId = dto.corridorId;
    if (dto.date) {
      const dayStart = new Date(`${dto.date.slice(0, 10)}T00:00:00`);
      where.departureTime = {
        gte: dayStart,
        lt: new Date(dayStart.getTime() + 24 * 60 * 60 * 1000),
      };
    }

    const [rows, total] = await Promise.all([
      this.prisma.trip.findMany({
        where,
        orderBy: { departureTime: 'desc' },
        skip: (page - 1) * perPage,
        take: perPage,
        include: { corridor: true, _count: { select: { bookings: true } } },
      }),
      this.prisma.trip.count({ where }),
    ]);

    // Trip.driverId is a plain FK → enrich driver info in bulk.
    const driverIds = [...new Set(rows.map((r) => r.driverId))];
    const drivers = await this.prisma.driverProfile.findMany({
      where: { id: { in: driverIds } },
      select: { id: true, ratingAvg: true, user: { select: { phone: true, name: true } } },
    });
    const driverMap = new Map(drivers.map((d) => [d.id, d]));

    const items = rows.map((r) => {
      const d = driverMap.get(r.driverId);
      return {
        id: r.id,
        status: r.status,
        departureTime: r.departureTime,
        seatsTotal: r.seatsTotal,
        seatsAvailable: r.seatsAvailable,
        pricePerSeat: r.pricePerSeat,
        corridor: { originCity: r.corridor.originCity, destCity: r.corridor.destCity },
        bookingCount: r._count.bookings,
        driver: d ? { phone: d.user.phone, name: d.user.name, ratingAvg: d.ratingAvg } : null,
      };
    });

    return { items, total, page, perPage };
  }

  private async setStatus(id: string, change: StatusChange) {
    const existing = await this.prisma.driverProfile.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException('السائق غير موجود.');
    }
    return this.prisma.driverProfile.update({
      where: { id },
      data: change,
      include: DRIVER_INCLUDE,
    });
  }

  private toCountMap(groups: Array<{ status: string; _count: { _all: number } }>): Record<string, number> {
    const map: Record<string, number> = {};
    for (const g of groups) map[g.status] = g._count._all;
    return map;
  }
}

function sum(map: Record<string, number>): number {
  return Object.values(map).reduce((a, b) => a + b, 0);
}
