/**
 * Numeral formatting — mirrors `packages/shared/lib/format/numerals.dart`, so
 * the admin panel prints numbers exactly the way the rider and driver apps do.
 *
 * ## The locked rule
 *
 * * **DISPLAY values render in ARABIC-INDIC numerals** (`٠١٢٣`): prices, seat
 *   counts, dates, dashboard counters. Thousands are grouped with the Arabic
 *   thousands separator `٬` (U+066C) — `١٢٬٠٠٠`.
 * * **INPUT fields stay WESTERN** (`0123`): the price field, the password
 *   field. A keyboard emits Western digits, so echoing Arabic-Indic back into
 *   the field being typed in causes real friction — and the value has to be
 *   parsed back to a number anyway.
 *
 * Never call {@link toArabicDigits} on the value of a text input. Going the
 * other way, {@link toWesternDigits} normalises anything pasted before parsing:
 * the wire format is always Western.
 */

/** U+066C ARABIC THOUSANDS SEPARATOR. */
export const ARABIC_THOUSANDS_SEPARATOR = "٬";

/** The Iraqi dinar suffix shown after a price. */
export const IQD_SUFFIX = "د.ع";

const WESTERN_ZERO = 0x30;
const ARABIC_ZERO = 0x0660;
const PERSIAN_ZERO = 0x06f0; // seen on some IMEs

/**
 * Converts Western digits `0-9` to Arabic-Indic `٠-٩`. Only digits are
 * touched, so this is safe over a string that already contains Arabic text
 * such as `د.ع` (whose `.` must NOT become a decimal separator).
 */
export function toArabicDigits(input: string): string {
  let out = "";
  for (const ch of input) {
    const code = ch.codePointAt(0)!;
    out +=
      code >= WESTERN_ZERO && code <= WESTERN_ZERO + 9
        ? String.fromCodePoint(ARABIC_ZERO + (code - WESTERN_ZERO))
        : ch;
  }
  return out;
}

/**
 * Converts Arabic-Indic and Persian digits back to Western `0-9`, and the
 * Arabic thousands separator back to `,`. Use before parsing or sending.
 */
export function toWesternDigits(input: string): string {
  let out = "";
  for (const ch of input) {
    const code = ch.codePointAt(0)!;
    if (code >= ARABIC_ZERO && code <= ARABIC_ZERO + 9) {
      out += String.fromCodePoint(WESTERN_ZERO + (code - ARABIC_ZERO));
    } else if (code >= PERSIAN_ZERO && code <= PERSIAN_ZERO + 9) {
      out += String.fromCodePoint(WESTERN_ZERO + (code - PERSIAN_ZERO));
    } else if (ch === ARABIC_THOUSANDS_SEPARATOR) {
      out += ",";
    } else {
      out += ch;
    }
  }
  return out;
}

/**
 * Groups into thousands with the Arabic separator, in Arabic-Indic digits —
 * `12000` → `١٢٬٠٠٠`. IQD has no minor unit, so amounts are whole dinars.
 */
export function formatIqd(amount: number): string {
  const digits = Math.abs(Math.trunc(amount)).toString();
  let grouped = "";
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) grouped += ARABIC_THOUSANDS_SEPARATOR;
    grouped += digits[i];
  }
  return toArabicDigits(`${amount < 0 ? "-" : ""}${grouped}`);
}

/** A price with the dinar suffix — `12000` → `١٢٬٠٠٠ د.ع`. */
export function formatPrice(amount: number): string {
  return `${formatIqd(amount)} ${IQD_SUFFIX}`;
}

/** A plain whole number in Arabic-Indic digits — counters, seat counts. */
export function formatCount(value: number): string {
  return toArabicDigits(Math.trunc(value).toString());
}

/**
 * A seat count as an Arabic noun phrase — `مقعد واحد` / `مقعدان` / `٣ مقاعد`.
 * Arabic has a dual, so two seats is "مقعدان", never "٢ مقاعد".
 */
export function formatSeats(count: number): string {
  if (count <= 0) return "لا مقاعد";
  if (count === 1) return "مقعد واحد";
  if (count === 2) return "مقعدان";
  return `${formatCount(count)} مقاعد`;
}

/**
 * A trip count as an Arabic noun phrase — `رحلة واحدة` / `رحلتان` / `٣ رحلات`.
 * Same dual rule as {@link formatSeats}: "٢ رحلات" is wrong Arabic, and so is
 * "٠ رحلة".
 */
export function formatTrips(count: number): string {
  if (count <= 0) return "لا رحلات";
  if (count === 1) return "رحلة واحدة";
  if (count === 2) return "رحلتان";
  return `${formatCount(count)} رحلات`;
}

/** Arabic (Levantine/Iraqi) month names, indexed 0–11. */
export const ARABIC_MONTHS = [
  "كانون الثاني",
  "شباط",
  "آذار",
  "نيسان",
  "أيار",
  "حزيران",
  "تموز",
  "آب",
  "أيلول",
  "تشرين الأول",
  "تشرين الثاني",
  "كانون الأول",
] as const;

/** Iraq is UTC+3 year-round (no DST). */
const BAGHDAD_OFFSET_MS = 3 * 60 * 60 * 1000;

/**
 * A timestamp as its **Baghdad** calendar day — `٢٠ تموز ٢٠٢٦`.
 *
 * The shift matters: rendering the raw UTC date files anything logged after
 * 21:00 Baghdad under the previous day.
 */
export function formatDate(value: string | Date): string {
  const dt = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(dt.getTime())) return "—";
  const baghdad = new Date(dt.getTime() + BAGHDAD_OFFSET_MS);
  return (
    `${toArabicDigits(String(baghdad.getUTCDate()))} ` +
    `${ARABIC_MONTHS[baghdad.getUTCMonth()]} ` +
    `${toArabicDigits(String(baghdad.getUTCFullYear()))}`
  );
}

/** A 1–5 rating with one decimal, Arabic-Indic — `4.8` → `٤٫٨`. */
export function formatRating(value: number): string {
  return toArabicDigits(value.toFixed(1)).replace(".", "٫");
}
