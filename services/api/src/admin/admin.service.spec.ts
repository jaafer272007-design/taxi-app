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

  it('approve() sets status APPROVED on an existing driver', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.PENDING });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.APPROVED });

    const result = await service.approve('d1');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'd1' }, data: { status: DriverStatus.APPROVED } }),
    );
    expect(result.status).toBe(DriverStatus.APPROVED);
  });

  it('approve() throws NotFound and does not update when the driver is missing', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue(null);

    await expect(service.approve('missing')).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.driverProfile.update).not.toHaveBeenCalled();
  });

  it('reject() sets status REJECTED', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.PENDING });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.REJECTED });

    const result = await service.reject('d1', 'blurry documents');

    expect(prisma.driverProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'd1' }, data: { status: DriverStatus.REJECTED } }),
    );
    expect(result.status).toBe(DriverStatus.REJECTED);
  });

  it('suspend() sets status SUSPENDED', async () => {
    prisma.driverProfile.findUnique.mockResolvedValue({ id: 'd1', status: DriverStatus.APPROVED });
    prisma.driverProfile.update.mockResolvedValue({ id: 'd1', status: DriverStatus.SUSPENDED });

    const result = await service.suspend('d1');

    expect(result.status).toBe(DriverStatus.SUSPENDED);
  });
});
