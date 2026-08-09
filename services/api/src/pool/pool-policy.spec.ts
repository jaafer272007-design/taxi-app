import {
  DEFAULT_POOL_POLICY,
  canProposeRaise,
  expiredPoolFilter,
  intersectWindows,
  isPoolLive,
  isViable,
  overlappingPoolFilter,
  poolJoinFilter,
  raiseDeadline,
  raiseRespondBy,
  readPoolPolicy,
  windowsOverlap,
} from './pool-policy';

const MIN = 60_000;
const at = (minutes: number) => new Date(Date.UTC(2026, 7, 9, 6, 0) + minutes * MIN);
const win = (startMin: number, endMin: number) => ({
  windowStart: at(startMin),
  windowEnd: at(endMin),
});

describe('the matching rule', () => {
  it('windows that share any instant overlap', () => {
    expect(windowsOverlap(win(0, 60), win(30, 90))).toBe(true);
    expect(windowsOverlap(win(30, 90), win(0, 60))).toBe(true);
  });

  it('one window entirely inside another overlaps', () => {
    expect(windowsOverlap(win(0, 120), win(30, 60))).toBe(true);
  });

  it('windows that merely touch DO overlap', () => {
    // That single instant is a departure time both riders accept, so refusing
    // it would be a rule we could not explain to either of them.
    expect(windowsOverlap(win(0, 60), win(60, 120))).toBe(true);
  });

  it('disjoint windows do not overlap', () => {
    expect(windowsOverlap(win(0, 60), win(61, 120))).toBe(false);
    expect(windowsOverlap(win(61, 120), win(0, 60))).toBe(false);
  });

  it('the intersection narrows, never widens', () => {
    const merged = intersectWindows(win(0, 90), win(30, 120));
    expect(merged.windowStart.toISOString()).toBe(at(30).toISOString());
    expect(merged.windowEnd.toISOString()).toBe(at(90).toISOString());
  });

  it('the intersection of nested windows is the inner one', () => {
    const merged = intersectWindows(win(0, 120), win(40, 50));
    expect(merged.windowStart.toISOString()).toBe(at(40).toISOString());
    expect(merged.windowEnd.toISOString()).toBe(at(50).toISOString());
  });
});

describe('the predicate and the query filter agree', () => {
  // The lesson that produced trip-window.ts: one rule written twice is exactly
  // the shape in which it drifts. These two encodings are checked against the
  // same fixtures so a change to one without the other fails here.
  const cases = [
    win(0, 60),
    win(30, 90),
    win(60, 120),
    win(61, 120),
    win(-120, -60),
    win(10, 20),
  ];

  it.each(cases.map((c, i) => [i, c]))('case %i', (_i, candidate) => {
    const want = win(0, 60);
    const filter = overlappingPoolFilter(want);

    // The Prisma filter, applied by hand — the same comparison the database
    // would make.
    const byFilter =
      (candidate as { windowStart: Date }).windowStart.getTime() <=
        (filter.windowStart as { lte: Date }).lte.getTime() &&
      (candidate as { windowEnd: Date }).windowEnd.getTime() >=
        (filter.windowEnd as { gte: Date }).gte.getTime();

    expect(byFilter).toBe(windowsOverlap(candidate, want));
  });
});

describe('the join guard', () => {
  const pool = win(0, 90);

  it('re-asserts the window it read — compare-and-swap, not read-then-write', () => {
    const where = poolJoinFilter('p1', pool, 2);
    // Without these two the guard would let a concurrent join that narrowed
    // the window slip us into a pool we no longer overlap.
    expect(where.windowStart).toEqual(pool.windowStart);
    expect(where.windowEnd).toEqual(pool.windowEnd);
  });

  it('caps seats so concurrent joins cannot exceed the vehicle', () => {
    const where = poolJoinFilter('p1', pool, 2, { ...DEFAULT_POOL_POLICY, maxSeats: 4 });
    expect(where.totalSeats).toEqual({ lte: 2 });
  });

  it('refuses a pool that is no longer FORMING', () => {
    expect(poolJoinFilter('p1', pool, 1).status).toBe('FORMING');
  });
});

describe('liveness', () => {
  const now = at(0);

  it('a pool whose window has not shut is live', () => {
    expect(isPoolLive(win(-30, 30), now)).toBe(true);
  });

  it('a pool whose window has shut is not', () => {
    expect(isPoolLive(win(-60, -1), now)).toBe(false);
  });

  it('the sweep filter is the exact complement', () => {
    const filter = expiredPoolFilter(now);
    for (const pool of [win(-60, -1), win(-30, 30), win(10, 20)]) {
      const bySweep = pool.windowEnd.getTime() <= (filter.windowEnd as { lte: Date }).lte.getTime();
      expect(bySweep).toBe(!isPoolLive(pool, now));
    }
  });
});

describe('viability', () => {
  it('needs the minimum seats', () => {
    expect(isViable(1)).toBe(false);
    expect(isViable(2)).toBe(true);
    expect(isViable(4)).toBe(true);
  });
});

describe('the raise deadlines', () => {
  const pool = win(120, 240); // departs at the earliest in two hours

  it('the blackout is measured from the START of the window', () => {
    // The trip may leave at the earliest time that suits everyone, so that is
    // what a rider who declines needs time before.
    expect(raiseDeadline(pool).toISOString()).toBe(at(90).toISOString());
  });

  it('a raise is allowed before the blackout and refused inside it', () => {
    expect(canProposeRaise(pool, DEFAULT_POOL_POLICY, at(89))).toBe(true);
    expect(canProposeRaise(pool, DEFAULT_POOL_POLICY, at(90))).toBe(false);
    expect(canProposeRaise(pool, DEFAULT_POOL_POLICY, at(100))).toBe(false);
  });

  it('the response deadline always lands BEFORE the window starts', () => {
    // Arithmetic, not taste: a raise is only possible before
    // windowStart − blackout, so respondBy ≤ windowStart − blackout + response,
    // and that is < windowStart exactly while response < blackout.
    expect(DEFAULT_POOL_POLICY.raiseResponseMinutes).toBeLessThan(
      DEFAULT_POOL_POLICY.raiseBlackoutMinutes,
    );
    const proposedAt = at(89); // the last legal instant
    const respondBy = raiseRespondBy(pool, DEFAULT_POOL_POLICY, proposedAt);
    expect(respondBy.getTime()).toBeLessThan(pool.windowStart.getTime());
  });

  it('clamps the response deadline to departure even if configured absurdly', () => {
    // A deadline that expires after the car has left decides the fate of
    // riders who are already on the road.
    const absurd = { ...DEFAULT_POOL_POLICY, raiseResponseMinutes: 600 };
    const respondBy = raiseRespondBy(pool, absurd, at(0));
    expect(respondBy.toISOString()).toBe(pool.windowStart.toISOString());
  });
});

describe('reading the environment', () => {
  const read = (env: Record<string, string | undefined>) =>
    readPoolPolicy((key) => env[key]);

  it('reads valid values', () => {
    const p = read({
      POOL_MAX_SEATS: '6',
      POOL_MIN_SEATS: '3',
      POOL_RAISE_BLACKOUT_MINUTES: '45',
      POOL_RAISE_RESPONSE_MINUTES: '15',
      POOL_MAX_WINDOW_HOURS: '4',
    });
    expect(p).toEqual({
      maxSeats: 6,
      minSeats: 3,
      raiseBlackoutMinutes: 45,
      raiseResponseMinutes: 15,
      maxWindowHours: 4,
    });
  });

  it.each([
    ['unset', undefined],
    ['blank', '  '],
    ['not a number', 'lots'],
    ['zero', '0'],
    ['negative', '-2'],
  ])('falls back to the default when %s', (_label, value) => {
    // A typo in an env var must not stop the service booting: these are policy
    // numbers, not engineering constants.
    expect(read({ POOL_MIN_SEATS: value as string | undefined }).minSeats).toBe(
      DEFAULT_POOL_POLICY.minSeats,
    );
  });

  it('rejects a minimum above the maximum — that board would always be empty', () => {
    const p = read({ POOL_MIN_SEATS: '9', POOL_MAX_SEATS: '4' });
    expect(p.minSeats).toBe(DEFAULT_POOL_POLICY.minSeats);
    expect(p.maxSeats).toBe(DEFAULT_POOL_POLICY.maxSeats);
  });

  it('defaults are the documented starting point', () => {
    expect(DEFAULT_POOL_POLICY).toEqual({
      maxSeats: 4,
      minSeats: 2,
      raiseBlackoutMinutes: 30,
      raiseResponseMinutes: 10,
      maxWindowHours: 6,
    });
  });
});
