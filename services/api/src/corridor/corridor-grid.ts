import { IRAQI_CITIES, IraqiCity } from './cities';

/**
 * The full corridor grid: every ordered pair of the 18 governorate hubs, priced
 * from distance.
 *
 * ## Why this exists
 *
 * Until driver-set pricing landed, a corridor carried THE fare, so seeding the
 * whole country would have meant asserting 306 real prices. Now a corridor only
 * carries a *suggestion* and a [min, max] band, and the driver names the actual
 * price — so a rough, honestly-labelled starting grid is safe and useful.
 *
 * ## The numbers are estimates, not survey data
 *
 * [CITY_COORDINATES] are approximate governorate-capital centroids, and prices
 * are derived from them by formula. They exist so every city pair is bookable on
 * day one with a *plausible* number, not an authoritative one. **The admin tunes
 * each corridor from the panel**, and the seed never overwrites a tuned price.
 *
 * Coordinates rather than a hand-written 153-entry distance matrix: 18 rows
 * instead of 153 means far less to mistype, the result is automatically
 * symmetric, and a wrong coordinate is obvious on a map in a way that a wrong
 * cell in a matrix is not.
 */

/** Approximate governorate-capital centroids (WGS-84 degrees). */
export const CITY_COORDINATES: Readonly<Record<IraqiCity, { lat: number; lng: number }>> = {
  Baghdad: { lat: 33.3152, lng: 44.3661 },
  Basra: { lat: 30.5085, lng: 47.7804 },
  Najaf: { lat: 31.9959, lng: 44.3148 },
  Karbala: { lat: 32.616, lng: 44.0242 },
  Erbil: { lat: 36.1911, lng: 44.0092 },
  Mosul: { lat: 36.335, lng: 43.1189 },
  Kirkuk: { lat: 35.4681, lng: 44.3922 },
  Sulaymaniyah: { lat: 35.5613, lng: 45.437 },
  Duhok: { lat: 36.8669, lng: 42.9883 },
  Ramadi: { lat: 33.4258, lng: 43.3089 },
  Baqubah: { lat: 33.75, lng: 44.6417 },
  Kut: { lat: 32.5126, lng: 45.8181 },
  Amarah: { lat: 31.8356, lng: 47.1447 },
  Nasiriyah: { lat: 31.0439, lng: 46.2575 },
  Samawah: { lat: 31.3327, lng: 45.281 },
  Diwaniyah: { lat: 31.9923, lng: 44.925 },
  Hilla: { lat: 32.4637, lng: 44.4197 },
  Tikrit: { lat: 34.61, lng: 43.6786 },
};

const EARTH_RADIUS_KM = 6371;

/**
 * Roads are not straight. This factor was CALIBRATED, not assumed: measured
 * against nine known road distances (Najaf–Karbala 80 km, Baghdad–Karbala 105,
 * Baghdad–Najaf 160, Baghdad–Hilla 100, Baghdad–Basra 550, Baghdad–Mosul 400,
 * Baghdad–Erbil 350, Baghdad–Kirkuk 240, Erbil–Duhok 150), 1.10 gives a mean
 * error of ~6%, against ~9% at 1.20 and ~11% at 1.25.
 *
 * It is low for a road network because Iraq's intercity trunk routes are mostly
 * straight desert highway. It correspondingly UNDERSTATES the winding routes
 * into the northern governorates — a single documented constant cannot be right
 * everywhere, and a per-pair correction would look like data while still being a
 * guess. The admin tunes the outliers.
 */
export const ROAD_CIRCUITY_FACTOR = 1.1;

/** What the rider pays before a single kilometre: pickup, waiting, the
 *  door-to-door detour at both ends. */
export const BASE_FARE_IQD = 3000;

/** Per-km rate for the first [NEAR_BAND_KM]. Chosen so the corridor already in
 *  service, Najaf→Karbala, lands exactly on its current 12,000 IQD. */
export const NEAR_RATE_IQD_PER_KM = 110;

/** Per-km rate beyond [NEAR_BAND_KM]. */
export const FAR_RATE_IQD_PER_KM = 55;

export const NEAR_BAND_KM = 100;

/**
 * Prices are rounded to the nearest 500 IQD. Iraqi fares are quoted in round
 * numbers, and a suggestion of "11,847" would read as false precision on a
 * figure that is an estimate anyway.
 */
export const PRICE_ROUNDING_IQD = 500;

/** The driver may charge from 60% to 160% of the suggestion. */
export const BAND_MIN_FACTOR = 0.6;
export const BAND_MAX_FACTOR = 1.6;

/** Great-circle distance in km between two coordinates. */
export function haversineKm(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);

  const h =
    Math.sin(dLat / 2) ** 2 + Math.sin(dLng / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

/** Estimated ROAD distance in km between two of the canonical cities. */
export function roadKmBetween(origin: IraqiCity, dest: IraqiCity): number {
  return haversineKm(CITY_COORDINATES[origin], CITY_COORDINATES[dest]) * ROAD_CIRCUITY_FACTOR;
}

/**
 * Suggested price per seat for a road distance, in IQD.
 *
 * Two tiers, because a flat per-km rate cannot fit both ends of the country. A
 * short hop is dominated by fixed cost (the base fare plus the first 100 km at
 * 110 IQD/km), while on a 500 km run the marginal kilometre is much cheaper —
 * at a single rate, anchoring the short trips would put Baghdad→Basra at roughly
 * double what a seat there actually costs.
 *
 * Anchored on the corridor already in service: Najaf→Karbala is ~74 km
 * straight-line, ~82 km by road, which lands exactly on 12,000 IQD — the price
 * in use. Everything else scales from there, and the long routes land close to
 * what a shared seat actually costs today:
 *   Karbala→Hilla     ~45 km →   8,000
 *   Baghdad→Najaf    ~161 km →  17,500
 *   Baghdad→Erbil    ~353 km →  28,000
 *   Baghdad→Basra    ~494 km →  35,500
 *   Basra→Duhok      ~918 km →  59,000
 */
export function suggestedPriceForKm(roadKm: number): number {
  const near = Math.min(roadKm, NEAR_BAND_KM);
  const far = Math.max(0, roadKm - NEAR_BAND_KM);
  const raw = BASE_FARE_IQD + near * NEAR_RATE_IQD_PER_KM + far * FAR_RATE_IQD_PER_KM;
  return roundToNearest(raw, PRICE_ROUNDING_IQD);
}

/**
 * The allowed band around a suggestion.
 *
 * `LEAST`/`GREATEST`-style clamping, exactly as the driver-set-pricing migration
 * does: rounding alone can push `min` above (or `max` below) the suggestion for
 * small numbers, and the invariant `0 < min <= suggested <= max` has to hold for
 * every row or the corridor is unusable — the driver's form would prefill a
 * value the very next POST /trips rejects.
 */
export function bandFor(suggested: number): { min: number; max: number } {
  const min = Math.min(
    suggested,
    Math.max(PRICE_ROUNDING_IQD, roundToNearest(suggested * BAND_MIN_FACTOR, PRICE_ROUNDING_IQD)),
  );
  const max = Math.max(
    suggested,
    roundToNearest(suggested * BAND_MAX_FACTOR, PRICE_ROUNDING_IQD),
  );
  return { min, max };
}

function roundToNearest(value: number, step: number): number {
  return Math.round(value / step) * step;
}

export interface CorridorSeed {
  originCity: IraqiCity;
  destCity: IraqiCity;
  suggestedPricePerSeat: number;
  minPricePerSeat: number;
  maxPricePerSeat: number;
  active: boolean;
}

/**
 * Every ORDERED pair of the canonical cities — 18 x 17 = 306 rows.
 *
 * Each direction is its own corridor because they are separate products: the
 * admin can price, activate or deactivate Najaf→Baghdad independently of
 * Baghdad→Najaf. The two currently receive the same price (distance is
 * symmetric), which is a starting point, not a constraint.
 */
export function buildCorridorGrid(): CorridorSeed[] {
  const rows: CorridorSeed[] = [];
  for (const originCity of IRAQI_CITIES) {
    for (const destCity of IRAQI_CITIES) {
      if (originCity === destCity) {
        continue;
      }
      const suggested = suggestedPriceForKm(roadKmBetween(originCity, destCity));
      const { min, max } = bandFor(suggested);
      rows.push({
        originCity,
        destCity,
        suggestedPricePerSeat: suggested,
        minPricePerSeat: min,
        maxPricePerSeat: max,
        active: true,
      });
    }
  }
  return rows;
}
