import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { DriverProfile, DriverStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const DRIVER_INCLUDE = {
  user: { select: { id: true, phone: true, name: true, roles: true, createdAt: true } },
  vehicle: true,
  documents: true,
} as const;

@Injectable()
export class AdminService {
  private readonly logger = new Logger(AdminService.name);

  constructor(private readonly prisma: PrismaService) {}

  /** List drivers (optionally filtered by status) with their vehicle + documents. */
  listDrivers(status?: DriverStatus) {
    return this.prisma.driverProfile.findMany({
      where: status ? { status } : {},
      include: DRIVER_INCLUDE,
    });
  }

  approve(id: string) {
    return this.setStatus(id, DriverStatus.APPROVED);
  }

  async reject(id: string, reason?: string) {
    // The Phase 1 schema (brief §2) has no rejection-reason column, so the
    // reason is logged rather than persisted.
    // TODO: persist the reason once a column is added to DriverProfile.
    if (reason) {
      this.logger.log(`Driver ${id} rejected. Reason: ${reason}`);
    }
    return this.setStatus(id, DriverStatus.REJECTED);
  }

  suspend(id: string) {
    return this.setStatus(id, DriverStatus.SUSPENDED);
  }

  private async setStatus(id: string, status: DriverStatus): Promise<DriverProfile> {
    const existing = await this.prisma.driverProfile.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException('السائق غير موجود.');
    }
    return this.prisma.driverProfile.update({
      where: { id },
      data: { status },
      include: DRIVER_INCLUDE,
    });
  }
}
