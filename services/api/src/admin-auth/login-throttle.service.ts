import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../redis/redis.service';

/**
 * Brute-force resistance for admin login.
 *
 * The counter key is **username + client IP**, not one or the other:
 *
 *  - IP alone lets one attacker behind a shared NAT lock out a whole office,
 *    and lets a botnet spread attempts across addresses for free.
 *  - Username alone lets anyone lock a known admin out of their own account by
 *    failing five logins on purpose.
 *
 * Combining them means an attacker must burn a fresh IP for every five guesses
 * against a given account, while a legitimate admin retrying from their own
 * connection is unaffected by anyone else's failures.
 *
 * Only FAILED attempts count, and a success clears the counter, so an admin who
 * fumbles their password four times and then gets it right starts clean.
 */
@Injectable()
export class LoginThrottleService {
  private readonly max: number;
  private readonly windowSeconds: number;

  constructor(
    private readonly redis: RedisService,
    config: ConfigService,
  ) {
    this.max = Number(config.get('ADMIN_LOGIN_RATE_LIMIT_MAX')) || 5;
    this.windowSeconds = Number(config.get('ADMIN_LOGIN_RATE_LIMIT_WINDOW_SECONDS')) || 900;
  }

  private key(username: string, ip: string): string {
    return `admin:login:fail:${username.toLowerCase()}:${ip}`;
  }

  /** Throws 429 when this username+IP pair has spent its attempt budget. */
  async assertNotLockedOut(username: string, ip: string): Promise<void> {
    const raw = await this.redis.get(this.key(username, ip));
    const failures = raw ? Number(raw) : 0;
    if (failures >= this.max) {
      throw new HttpException(
        'محاولات دخول كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  async recordFailure(username: string, ip: string): Promise<void> {
    await this.redis.incrWithWindow(this.key(username, ip), this.windowSeconds);
  }

  async clear(username: string, ip: string): Promise<void> {
    await this.redis.del(this.key(username, ip));
  }
}
