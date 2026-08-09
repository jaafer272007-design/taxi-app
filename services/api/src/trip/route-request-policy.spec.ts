import {
  DEFAULT_ROUTE_REQUEST_POLICY,
  baghdadDayKey,
  isWithinTtl,
  outstandingSince,
  readRouteRequestPolicy,
} from './route-request-policy';

const DAY_MS = 24 * 60 * 60 * 1000;

describe('route-request policy — the TTL', () => {
  const now = new Date('2026-08-09T12:00:00.000Z');

  it('defaults to 30 days', () => {
    expect(DEFAULT_ROUTE_REQUEST_POLICY.ttlDays).toBe(30);
  });

  it('a request from yesterday is still live; one from 31 days ago is not', () => {
    expect(isWithinTtl(new Date(now.getTime() - DAY_MS), undefined, now)).toBe(true);
    expect(isWithinTtl(new Date(now.getTime() - 31 * DAY_MS), undefined, now)).toBe(false);
  });

  it('outstandingSince and isWithinTtl agree on the same instant', () => {
    // The fan-out uses the cutoff as a query bound and the admin aggregate uses
    // the same one. If they ever disagreed the panel would show an admin demand
    // whose owner will never be notified — so they are asserted together.
    const cutoff = outstandingSince(undefined, now);
    expect(isWithinTtl(new Date(cutoff.getTime() + 1), undefined, now)).toBe(true);
    expect(isWithinTtl(cutoff, undefined, now)).toBe(false);
  });

  it('honours a custom window', () => {
    const policy = { ttlDays: 7 };
    expect(isWithinTtl(new Date(now.getTime() - 6 * DAY_MS), policy, now)).toBe(true);
    expect(isWithinTtl(new Date(now.getTime() - 8 * DAY_MS), policy, now)).toBe(false);
  });
});

describe('route-request policy — reading the environment', () => {
  const read = (value: string | undefined) =>
    readRouteRequestPolicy((key) =>
      key === 'ROUTE_REQUEST_TTL_DAYS' ? value : undefined,
    );

  it('reads a valid value', () => {
    expect(read('14').ttlDays).toBe(14);
  });

  it.each([
    ['unset', undefined],
    ['blank', '   '],
    ['not a number', 'soon'],
    ['zero', '0'],
    ['negative', '-5'],
  ])('falls back to the default when %s', (_label, value) => {
    // A typo in an env var must not stop the service booting: these are policy
    // numbers, not engineering constants. Same rule as the no-show policy.
    expect(read(value as string | undefined).ttlDays).toBe(
      DEFAULT_ROUTE_REQUEST_POLICY.ttlDays,
    );
  });

  it('floors a fractional value rather than storing 2.5 days', () => {
    expect(read('2.5').ttlDays).toBe(2);
  });
});

describe('route-request policy — the Baghdad day key', () => {
  it('is the calendar day in Asia/Baghdad, not UTC', () => {
    // 22:00 Baghdad on the 9th is 19:00Z on the 9th — same day either way.
    expect(baghdadDayKey(new Date('2026-08-09T19:00:00.000Z')).toISOString()).toBe(
      '2026-08-09T00:00:00.000Z',
    );
  });

  it('THE TRAP: 22:00 Baghdad is still today, though UTC has not turned over', () => {
    // 2026-08-09T22:00 Baghdad = 2026-08-09T19:00Z. A naive
    // `toISOString().slice(0,10)` agrees here — the failure is the next case.
    const evening = baghdadDayKey(new Date('2026-08-09T19:00:00.000Z'));
    const lateEvening = baghdadDayKey(new Date('2026-08-09T20:59:00.000Z'));
    expect(lateEvening.toISOString()).toBe(evening.toISOString());
  });

  it('THE TRAP, the half that bites: 01:00 Baghdad is a NEW day', () => {
    // 2026-08-10T01:00 Baghdad = 2026-08-09T22:00Z. UTC still says the 9th, so
    // a UTC-based key would fold a 1am tap into the previous day — and a rider
    // who tapped at 23:00 and again at 01:00 would silently get ONE row for
    // what are two different days to them.
    const beforeMidnight = baghdadDayKey(new Date('2026-08-09T20:00:00.000Z')); // 23:00 Baghdad
    const afterMidnight = baghdadDayKey(new Date('2026-08-09T22:00:00.000Z')); // 01:00 Baghdad
    expect(beforeMidnight.toISOString()).toBe('2026-08-09T00:00:00.000Z');
    expect(afterMidnight.toISOString()).toBe('2026-08-10T00:00:00.000Z');
    expect(afterMidnight.getTime()).toBeGreaterThan(beforeMidnight.getTime());

    // And the control: the naive UTC key gets this wrong, which is why the
    // helper exists at all.
    expect(new Date('2026-08-09T22:00:00.000Z').toISOString().slice(0, 10)).toBe(
      '2026-08-09',
    );
  });

  it('lands exactly on midnight Baghdad', () => {
    // 21:00Z is 00:00 Baghdad the next day — the first instant of the new key.
    expect(baghdadDayKey(new Date('2026-08-09T20:59:59.999Z')).toISOString()).toBe(
      '2026-08-09T00:00:00.000Z',
    );
    expect(baghdadDayKey(new Date('2026-08-09T21:00:00.000Z')).toISOString()).toBe(
      '2026-08-10T00:00:00.000Z',
    );
  });

  it('always returns UTC midnight, because the column is a DATE', () => {
    for (const iso of [
      '2026-01-01T00:00:00.000Z',
      '2026-06-15T11:22:33.444Z',
      '2026-12-31T23:59:59.999Z',
    ]) {
      const key = baghdadDayKey(new Date(iso));
      expect(key.getUTCHours()).toBe(0);
      expect(key.getUTCMinutes()).toBe(0);
      expect(key.getUTCSeconds()).toBe(0);
      expect(key.getUTCMilliseconds()).toBe(0);
    }
  });
});
