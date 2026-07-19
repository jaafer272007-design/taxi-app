/**
 * Canonical Iraqi cities — one hub per governorate (18 total). The KEY is the
 * value stored in `Corridor.originCity` / `Corridor.destCity`; the Arabic display
 * name lives client-side (see packages/shared iraqi_cities.dart, kept in sync).
 *
 * A corridor may only be created between two of these cities (validated in the
 * corridor DTOs). Keeping the canonical set here — not free-text — is what makes
 * "any two cities" safe: the admin picks from this list, never a typo.
 */
export const IRAQI_CITIES = [
  'Baghdad', // بغداد
  'Basra', // البصرة
  'Najaf', // النجف
  'Karbala', // كربلاء
  'Erbil', // أربيل
  'Mosul', // الموصل (نينوى)
  'Kirkuk', // كركوك
  'Sulaymaniyah', // السليمانية
  'Duhok', // دهوك
  'Ramadi', // الرمادي (الأنبار)
  'Baqubah', // بعقوبة (ديالى)
  'Kut', // الكوت (واسط)
  'Amarah', // العمارة (ميسان)
  'Nasiriyah', // الناصرية (ذي قار)
  'Samawah', // السماوة (المثنى)
  'Diwaniyah', // الديوانية (القادسية)
  'Hilla', // الحلة (بابل)
  'Tikrit', // تكريت (صلاح الدين)
] as const;

export type IraqiCity = (typeof IRAQI_CITIES)[number];

const CITY_SET: ReadonlySet<string> = new Set(IRAQI_CITIES);

/** Whether [value] is one of the canonical Iraqi cities. */
export function isIraqiCity(value: string): boolean {
  return CITY_SET.has(value);
}
