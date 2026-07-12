import { Injectable, OnModuleDestroy, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private readonly client: Redis;

  constructor(config: ConfigService) {
    const url = config.getOrThrow<string>('REDIS_URL');
    this.client = new Redis(url, { maxRetriesPerRequest: 3 });
    this.client.on('error', (err) => this.logger.error(`Redis error: ${err.message}`));
  }

  get raw(): Redis {
    return this.client;
  }

  /** Set a value with a TTL (seconds). */
  async setEx(key: string, value: string, ttlSeconds: number): Promise<void> {
    await this.client.set(key, value, 'EX', ttlSeconds);
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async del(...keys: string[]): Promise<void> {
    if (keys.length) await this.client.del(...keys);
  }

  /**
   * Increment a counter and make sure it expires after `windowSeconds`.
   * The TTL is set only when the counter is first created, so the window
   * is fixed from the first hit. Returns the new counter value.
   */
  async incrWithWindow(key: string, windowSeconds: number): Promise<number> {
    const count = await this.client.incr(key);
    if (count === 1) {
      await this.client.expire(key, windowSeconds);
    }
    return count;
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.quit();
  }
}
