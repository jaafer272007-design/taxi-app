/**
 * Canonical Iraqi cities — one hub per governorate (18 total). `key` is the
 * value stored server-side in `Corridor.originCity` / `destCity`; `ar` is the
 * Arabic display name. This list MUST stay in sync with the other two
 * mirrors: `services/api/src/corridor/cities.ts` (backend validation) and
 * `packages/shared/lib/constants/iraqi_cities.dart` (rider/driver apps).
 */
export interface IraqiCity {
  key: string;
  ar: string;
}

export const IRAQI_CITIES: readonly IraqiCity[] = [
  { key: "Baghdad", ar: "بغداد" },
  { key: "Basra", ar: "البصرة" },
  { key: "Najaf", ar: "النجف" },
  { key: "Karbala", ar: "كربلاء" },
  { key: "Erbil", ar: "أربيل" },
  { key: "Mosul", ar: "الموصل" },
  { key: "Kirkuk", ar: "كركوك" },
  { key: "Sulaymaniyah", ar: "السليمانية" },
  { key: "Duhok", ar: "دهوك" },
  { key: "Ramadi", ar: "الرمادي" },
  { key: "Baqubah", ar: "بعقوبة" },
  { key: "Kut", ar: "الكوت" },
  { key: "Amarah", ar: "العمارة" },
  { key: "Nasiriyah", ar: "الناصرية" },
  { key: "Samawah", ar: "السماوة" },
  { key: "Diwaniyah", ar: "الديوانية" },
  { key: "Hilla", ar: "الحلة" },
  { key: "Tikrit", ar: "تكريت" },
];

const CITY_KEYS = IRAQI_CITIES.map((c) => c.key) as [string, ...string[]];

const cityArByKey = new Map(IRAQI_CITIES.map((c) => [c.key, c.ar]));

/** Arabic display name for a stored city key; falls back to the key itself. */
export function cityAr(key: string): string {
  return cityArByKey.get(key) ?? key;
}

/** All valid city keys, for zod `z.enum()` validation. */
export const CITY_KEY_TUPLE = CITY_KEYS;
