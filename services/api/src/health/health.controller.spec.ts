import { HealthController } from './health.controller';

describe('HealthController', () => {
  it('returns an ok liveness payload with a parseable timestamp', () => {
    const res = new HealthController().check();

    expect(res.status).toBe('ok');
    expect(res.service).toBe('taxi-api');
    expect(typeof res.tz).toBe('string');
    expect(Number.isNaN(Date.parse(res.time))).toBe(false);
  });
});
