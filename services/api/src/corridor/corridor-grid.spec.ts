import { IRAQI_CITIES } from './cities';
import {
  bandFor,
  buildCorridorGrid,
  CITY_COORDINATES,
  haversineKm,
  roadKmBetween,
  suggestedPriceForKm,
  PRICE_ROUNDING_IQD,
} from './corridor-grid';

describe('corridor grid', () => {
  const grid = buildCorridorGrid();

  describe('coverage', () => {
    it('is every ORDERED pair of the 18 cities — 306 rows', () => {
      expect(IRAQI_CITIES).toHaveLength(18);
      expect(grid).toHaveLength(18 * 17);
    });

    it('has a coordinate for every canonical city, and no extras', () => {
      // A city in the list without a coordinate would throw NaN prices; a
      // coordinate without a city is dead weight that will drift.
      expect(Object.keys(CITY_COORDINATES).sort()).toEqual([...IRAQI_CITIES].sort());
    });

    it('never pairs a city with itself', () => {
      expect(grid.filter((r) => r.originCity === r.destCity)).toHaveLength(0);
    });

    it('has no duplicate (origin, dest) pairs', () => {
      const keys = new Set(grid.map((r) => `${r.originCity}→${r.destCity}`));
      expect(keys.size).toBe(grid.length);
    });

    it('covers both directions of every pair', () => {
      for (const row of grid) {
        const reverse = grid.find(
          (r) => r.originCity === row.destCity && r.destCity === row.originCity,
        );
        expect(reverse).toBeDefined();
      }
    });

    it('marks every corridor active', () => {
      expect(grid.every((r) => r.active)).toBe(true);
    });
  });

  describe('the price invariant, on every row', () => {
    it('holds 0 < min <= suggested <= max for all 306', () => {
      const broken = grid.filter(
        (r) =>
          !(
            r.minPricePerSeat > 0 &&
            r.minPricePerSeat <= r.suggestedPricePerSeat &&
            r.suggestedPricePerSeat <= r.maxPricePerSeat
          ),
      );
      expect(broken).toEqual([]);
    });

    it('uses whole dinars everywhere — IQD has no fractions', () => {
      const fractional = grid.filter((r) =>
        [r.minPricePerSeat, r.suggestedPricePerSeat, r.maxPricePerSeat].some(
          (v) => !Number.isInteger(v),
        ),
      );
      expect(fractional).toEqual([]);
    });

    it('rounds every price to a payable figure', () => {
      const unrounded = grid.filter((r) =>
        [r.minPricePerSeat, r.suggestedPricePerSeat, r.maxPricePerSeat].some(
          (v) => v % PRICE_ROUNDING_IQD !== 0,
        ),
      );
      expect(unrounded).toEqual([]);
    });

    it('holds even where rounding fights the band', () => {
      // The clamp exists for exactly this: at a small suggestion, 60% and 160%
      // can both round back onto the suggestion itself.
      for (const suggested of [500, 1000, 1500, 2000, 8000, 12000, 59000]) {
        const { min, max } = bandFor(suggested);
        expect(min).toBeGreaterThan(0);
        expect(min).toBeLessThanOrEqual(suggested);
        expect(max).toBeGreaterThanOrEqual(suggested);
      }
    });
  });

  describe('prices scale with distance', () => {
    it('is anchored on the corridor already in service', () => {
      // Najaf→Karbala is priced at 12,000 today. The formula reproduces it, so
      // the rest of the grid is scaled from a real number rather than a guess.
      const najafKarbala = grid.find(
        (r) => r.originCity === 'Najaf' && r.destCity === 'Karbala',
      );
      expect(najafKarbala?.suggestedPricePerSeat).toBe(12000);
    });

    it('does NOT price every corridor the same', () => {
      // The whole point of the exercise: a Najaf↔Karbala band and a Najaf↔Duhok
      // band cannot be the same number.
      const distinct = new Set(grid.map((r) => r.suggestedPricePerSeat));
      expect(distinct.size).toBeGreaterThan(20);
    });

    it('charges more for a longer trip, monotonically', () => {
      const ordered = [...grid].sort(
        (a, b) =>
          roadKmBetween(a.originCity, a.destCity) - roadKmBetween(b.originCity, b.destCity),
      );
      for (let i = 1; i < ordered.length; i++) {
        expect(ordered[i].suggestedPricePerSeat).toBeGreaterThanOrEqual(
          ordered[i - 1].suggestedPricePerSeat,
        );
      }
    });

    it('puts a cross-country seat well above a neighbouring-city one', () => {
      const short = grid.find((r) => r.originCity === 'Karbala' && r.destCity === 'Hilla')!;
      const long = grid.find((r) => r.originCity === 'Basra' && r.destCity === 'Duhok')!;
      expect(long.suggestedPricePerSeat).toBeGreaterThan(short.suggestedPricePerSeat * 5);
    });

    it('prices both directions of a pair identically (distance is symmetric)', () => {
      for (const row of grid) {
        const reverse = grid.find(
          (r) => r.originCity === row.destCity && r.destCity === row.originCity,
        )!;
        expect(reverse.suggestedPricePerSeat).toBe(row.suggestedPricePerSeat);
      }
    });

    it('stays inside a sane envelope for the whole country', () => {
      // A guard against a coordinate typo silently producing a 500,000 IQD seat.
      const prices = grid.map((r) => r.suggestedPricePerSeat);
      expect(Math.min(...prices)).toBeGreaterThanOrEqual(5000);
      expect(Math.max(...prices)).toBeLessThanOrEqual(80000);
    });
  });

  describe('distance estimates', () => {
    it('is symmetric', () => {
      expect(roadKmBetween('Najaf', 'Karbala')).toBeCloseTo(
        roadKmBetween('Karbala', 'Najaf'),
        6,
      );
    });

    it('lands within ~15% of known road distances', () => {
      // Not survey data — but if a coordinate is wrong these blow out badly.
      const known: Array<[Parameters<typeof roadKmBetween>[0], Parameters<typeof roadKmBetween>[1], number]> = [
        ['Najaf', 'Karbala', 80],
        ['Baghdad', 'Karbala', 105],
        ['Baghdad', 'Najaf', 160],
        ['Baghdad', 'Basra', 550],
        ['Baghdad', 'Mosul', 400],
        ['Baghdad', 'Erbil', 350],
        ['Erbil', 'Duhok', 150],
      ];
      for (const [origin, dest, realKm] of known) {
        const estimate = roadKmBetween(origin, dest);
        expect(Math.abs(estimate - realKm) / realKm).toBeLessThan(0.15);
      }
    });

    it('haversine agrees with a known great-circle distance', () => {
      // Baghdad→Basra straight-line is ~450 km.
      expect(haversineKm(CITY_COORDINATES.Baghdad, CITY_COORDINATES.Basra)).toBeCloseTo(
        449,
        -1,
      );
    });

    it('is zero for a city against itself', () => {
      expect(haversineKm(CITY_COORDINATES.Najaf, CITY_COORDINATES.Najaf)).toBe(0);
    });
  });

  describe('suggestedPriceForKm', () => {
    it('never returns a non-positive price, even at zero distance', () => {
      expect(suggestedPriceForKm(0)).toBeGreaterThan(0);
    });

    it('is cheaper per km on a long trip than a short one', () => {
      // The two-tier rate exists precisely so this is true — a flat rate would
      // put a cross-country seat at roughly double what it really costs.
      const shortPerKm = suggestedPriceForKm(50) / 50;
      const longPerKm = suggestedPriceForKm(500) / 500;
      expect(longPerKm).toBeLessThan(shortPerKm);
    });
  });
});
