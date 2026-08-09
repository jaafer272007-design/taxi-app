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

/**
 * Arabic display names — the FOURTH mirror of this list, and deliberate.
 *
 * The other three are client-side (`packages/shared/.../iraqi_cities.dart`,
 * `apps/admin/src/lib/cities.ts`) plus the key list above. This one exists
 * because **notification copy is composed server-side** — the locked rule in
 * `notification`: `title`/`body` are stored ready to render so the centre never
 * re-derives them from ids whose rows may since have changed.
 *
 * Without it, a ROUTE_AVAILABLE notification would read «Najaf إلى Karbala» —
 * the exact bug the admin panel shipped and its E2E caught. There is no way to
 * translate at read time that does not break the stored-copy rule.
 *
 * The duplication is only safe because it is CHECKED: `cities.spec.ts` asserts
 * this map covers every key in {@link IRAQI_CITIES}, so a nineteenth city
 * cannot ship half-translated.
 */
const CITY_AR: Readonly<Record<string, string>> = {
  Baghdad: 'بغداد',
  Basra: 'البصرة',
  Najaf: 'النجف',
  Karbala: 'كربلاء',
  Erbil: 'أربيل',
  Mosul: 'الموصل',
  Kirkuk: 'كركوك',
  Sulaymaniyah: 'السليمانية',
  Duhok: 'دهوك',
  Ramadi: 'الرمادي',
  Baqubah: 'بعقوبة',
  Kut: 'الكوت',
  Amarah: 'العمارة',
  Nasiriyah: 'الناصرية',
  Samawah: 'السماوة',
  Diwaniyah: 'الديوانية',
  Hilla: 'الحلة',
  Tikrit: 'تكريت',
};

/**
 * Arabic name for a stored city key, falling back to the key itself.
 *
 * The fallback is not a silent failure to hide: a stored key that is not in the
 * canonical list is already impossible (the DTOs validate against it), and
 * showing the raw key beats showing nothing if one ever appears.
 */
export function cityAr(key: string): string {
  return CITY_AR[key] ?? key;
}

/**
 * «النجف إلى كربلاء» — the ONE way to name a route in user-facing copy.
 *
 * Joined with the word «إلى», never an arrow: the bundled Cairo has no arrow
 * glyph and `→` renders as a tofu box (CLAUDE.md → Glyph coverage). The apps
 * follow the same rule; this is its server-side half.
 */
export function routeLabelAr(originCity: string, destCity: string): string {
  return `${cityAr(originCity)} إلى ${cityAr(destCity)}`;
}
