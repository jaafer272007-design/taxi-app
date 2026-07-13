import { NotFoundException } from '@nestjs/common';
import { DriverStatus } from '@prisma/client';
import { AdminService } from './admin.service';
import { PrismaService } from '../prisma/prisma.service';

describe('AdminService', () => {
  let prisma: {
    driverProfile: { findUnique: jest.Mock; update: jest.Mock; findMany: jest.Mock };
  };
  let service: AdminService;

  beforeEach(() => {
    prisma = {
      driverProfile: {
        findUnique: jest.fn(),
        update: jest.fn(),
        findMany: jest.fn(),
      },
    };
    service = new AdminService(prisma as unknown as PrismaService);
  });

  it('approve() sets APPROVED and clears any rejection reason', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.REJECTED });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.APPROVED });

    await service.approve('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'd1' },
        data: { status: DriverStatus.APPROVED, rejectionReason: null },
      }),
    );
  });

  it('approve() throws NotFound and does not update when the driver is missing', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue(null);
    await expect(service.approve('missing')).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.driverProfile.update).not.toHaveBeenCalled();
  });

  it('reject() persists the reason', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.PENDING });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.REJECTED });

    await service.reject('d1', 'blurry documents');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'd1' },
        data: { status: DriverStatus.REJECTED, rejectionReason: 'blurry documents' },
      }),
    );
  });

  it('reject() with no reason stores null', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.PENDING });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.REJECTED });

    await service.reject('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { status: DriverStatus.REJECTED, rejectionReason: null },
      }),
    );
  });

  it('suspend() sets SUSPENDED without touching rejectionReason', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.APPROVED });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.SUSPENDED });

    await service.suspend('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'd1' }, data: { status: DriverStatus.SUSPENDED } }),
    );
  });
});
