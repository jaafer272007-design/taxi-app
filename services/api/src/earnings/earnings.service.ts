import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';

@Injectable()
export class EarningsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriverService,
  ) {}

  /** Driver's cash earnings from EarningsRecord: total + per-trip breakdown. */
  async getEarnings(userId: string, range: 'today' | 'all' = 'all') {
    const profile = await this.drivers.findProfileByUserId(userId);
    if (!profile) {
      return { range, total: 0, records: [] };
    }

    const where: Prisma.EarningsRecordWhereInput = { driverId: profile.id };
    if (range === 'today') {
      const now = new Date();
      // Local midnight = Asia/Baghdad midnight (process TZ).
      const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      where.collectedAt = { gte: startOfToday };
    }

    const records = await this.prisma.earningsRecord.findMany({
      where,
      orderBy: { collectedAt: 'desc' },
    });
    const total = records.reduce((sum, r) => sum + r.amount, 0);
    return { range, total, records };
  }
}
