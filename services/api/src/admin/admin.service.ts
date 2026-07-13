import { Injectable, NotFoundException } from '@nestjs/common';
import { DriverProfile, DriverStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

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
  constructor(private readonly prisma: PrismaService) {}

  /** List drivers (optionally filtered by status) with their vehicle + documents. */
  listDrivers(status?: DriverStatus) {
    return this.prisma.driverProfile.findMany({
      where: status ? { status } : {},
      include: DRIVER_INCLUDE,
    });
  }

  approve(id: string) {
    // Clear any stale rejection reason when a driver is (re-)approved.
    return this.setStatus(id, { status: DriverStatus.APPROVED, rejectionReason: null });
  }

  reject(id: string, reason?: string) {
    return this.setStatus(id, { status: DriverStatus.REJECTED, rejectionReason: reason ?? null });
  }

  suspend(id: string) {
    // Suspension is not a rejection — leave rejectionReason untouched.
    return this.setStatus(id, { status: DriverStatus.SUSPENDED });
  }

  private async setStatus(id: string, change: StatusChange): Promise<DriverProfile> {
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
}
