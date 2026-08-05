import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { expireStaleTrips } from './trip-expiry';

/**
 * Retires trips whose window has shut. Resolves the `TODO(Step 4/5)` that used
 * to sit on the departNow window.
 *
 * A scheduler rather than a sweep on the read path: search is a rider's hottest
 * request and has no business doing writes, and hanging cleanup off "somebody
 * happened to look" means a trip nobody looks at stays OPEN forever — which is
 * the thing this is supposed to prevent.
 *
 * Rider-visibility does NOT depend on this job. An expired trip is already
 * excluded by `catchableTripFilter` in search and refused by the booking guard,
 * so if the job never ran the worst outcome is stale rows in the driver's list
 * and the admin counters, not a bookable ghost trip. That separation is
 * deliberate: correctness in the query, tidiness on the schedule.
 */
@Injectable()
export class TripExpiryJob {
  private readonly logger = new Logger(TripExpiryJob.name);

  constructor(private readonly prisma: PrismaService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async sweep(): Promise<void> {
    try {
      const { locked, cancelled } = await expireStaleTrips(this.prisma);
      if (locked || cancelled) {
        this.logger.log(`Retired expired trips: ${locked} locked, ${cancelled} cancelled`);
      }
    } catch (err) {
      // A failed sweep must not take the process down — the next tick retries,
      // and nothing rider-facing depends on it having run.
      this.logger.error(`Trip expiry sweep failed: ${(err as Error).message}`);
    }
  }
}
