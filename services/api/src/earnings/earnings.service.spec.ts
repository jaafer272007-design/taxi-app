import { EarningsService } from './earnings.service';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';

describe('EarningsService.getEarnings', () => {
  let prisma: any;
  let drivers: any;
  let service: EarningsService;

  beforeEach(() => {
    prisma = { earningsRecord: { findMany: jest.fn() } };
    drivers = { findProfileByUserId: jest.fn() };
    service = new EarningsService(prisma as PrismaService, drivers as DriverService);
  });

  it('returns zero for a non-driver without querying', async () => {
    drivers.findProfileByUserId.mockResolvedValue(null);
    const r = await service.getEarnings('u1', 'all');
    expect(r).toEqual({ range: 'all', total: 0, records: [] });
    expect(prisma.earningsRecord.findMany).not.toHaveBeenCalled();
  });

  it('sums the driver records', async () => {
    drivers.findProfileByUserId.mockResolvedValue({ id: 'drv1' });
    prisma.earningsRecord.findMany.mockResolvedValue([{ amount: 6000 }, { amount: 12000 }]);
    const r = await service.getEarnings('u1', 'all');
    expect(r.total).toBe(18000);
    expect(r.records).toHaveLength(2);
  });

  it('adds a collectedAt lower bound for range=today', async () => {
    drivers.findProfileByUserId.mockResolvedValue({ id: 'drv1' });
    prisma.earningsRecord.findMany.mockResolvedValue([{ amount: 5000 }]);
    await service.getEarnings('u1', 'today');
    const where = prisma.earningsRecord.findMany.mock.calls[0][0].where;
    expect(where.driverId).toBe('drv1');
    expect(where.collectedAt).toHaveProperty('gte');
  });
});
