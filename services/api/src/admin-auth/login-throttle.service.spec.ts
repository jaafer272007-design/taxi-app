import { ConfigService } from '@nestjs/config';
import { HttpException } from '@nestjs/common';
import { LoginThrottleService } from './login-throttle.service';
import { RedisService } from '../redis/redis.service';

/** An in-memory stand-in for the two Redis calls the throttle uses. */
function fakeRedis() {
  const store = new Map<string, number>();
  return {
    store,
    get: jest.fn(async (k: string) => (store.has(k) ? String(store.get(k)) : null)),
    incrWithWindow: jest.fn(async (k: string) => {
      const next = (store.get(k) ?? 0) + 1;
      store.set(k, next);
      return next;
    }),
    del: jest.fn(async (...keys: string[]) => {
      keys.forEach((k) => store.delete(k));
    }),
  };
}

function config(values: Record<string, string> = {}) {
  return { get: (k: string) => values[k] } as unknown as ConfigService;
}

describe('LoginThrottleService', () => {
  it('allows exactly 5 failures, then locks out', async () => {
    const redis = fakeRedis();
    const throttle = new LoginThrottleService(redis as unknown as RedisService, config());

    for (let i = 0; i < 5; i++) {
      await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).resolves.toBeUndefined();
      await throttle.recordFailure('ali', '1.2.3.4');
    }

    await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).rejects.toThrow(HttpException);
  });

  it('keys on username AND ip together', async () => {
    const redis = fakeRedis();
    const throttle = new LoginThrottleService(redis as unknown as RedisService, config());

    for (let i = 0; i < 5; i++) await throttle.recordFailure('ali', '1.2.3.4');

    // Same admin, different network → not punished for someone else's attempts.
    await expect(throttle.assertNotLockedOut('ali', '9.9.9.9')).resolves.toBeUndefined();
    // Same network, different admin → likewise. Keying on IP alone would let a
    // shared office connection lock everyone out at once.
    await expect(throttle.assertNotLockedOut('zainab', '1.2.3.4')).resolves.toBeUndefined();
    // The exhausted pair is still locked.
    await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).rejects.toThrow(HttpException);
  });

  it('a success clears the counter', async () => {
    const redis = fakeRedis();
    const throttle = new LoginThrottleService(redis as unknown as RedisService, config());

    for (let i = 0; i < 4; i++) await throttle.recordFailure('ali', '1.2.3.4');
    await throttle.clear('ali', '1.2.3.4');

    for (let i = 0; i < 5; i++) {
      await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).resolves.toBeUndefined();
      await throttle.recordFailure('ali', '1.2.3.4');
    }
    await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).rejects.toThrow(HttpException);
  });

  it('is case-insensitive, so ALI and ali share one budget', async () => {
    const redis = fakeRedis();
    const throttle = new LoginThrottleService(redis as unknown as RedisService, config());

    for (let i = 0; i < 5; i++) await throttle.recordFailure('ALI', '1.2.3.4');

    await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).rejects.toThrow(HttpException);
  });

  it('honours the configured maximum', async () => {
    const redis = fakeRedis();
    const throttle = new LoginThrottleService(
      redis as unknown as RedisService,
      config({ ADMIN_LOGIN_RATE_LIMIT_MAX: '2' }),
    );

    await throttle.recordFailure('ali', '1.2.3.4');
    await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).resolves.toBeUndefined();
    await throttle.recordFailure('ali', '1.2.3.4');
    await expect(throttle.assertNotLockedOut('ali', '1.2.3.4')).rejects.toThrow(HttpException);
  });
});
