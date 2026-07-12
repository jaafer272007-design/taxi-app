/**
 * Iraqi (+964) mobile phone handling.
 *
 * Iraqi mobile numbers are 10 national digits starting with `7` (e.g. Zain 077x,
 * Asiacell 078x, Korek 075x → without the trunk `0`: 7xxxxxxxxx). In E.164 that
 * is `+964` followed by those 10 digits: `+9647XXXXXXXXX` (13 chars total).
 *
 * `normalizeIraqiPhone` accepts the common ways users type it and returns the
 * canonical E.164 form, or `null` if it is not a valid Iraqi mobile number.
 */
const E164_IRAQI_MOBILE = /^\+9647\d{9}$/;

export function normalizeIraqiPhone(input: string): string | null {
  if (typeof input !== 'string') return null;

  // Strip everything except digits and a leading '+'.
  let s = input.trim().replace(/[\s\-().]/g, '');

  // 00 international prefix → +
  if (s.startsWith('00')) s = '+' + s.slice(2);

  let national: string;
  if (s.startsWith('+964')) {
    national = s.slice(4);
  } else if (s.startsWith('964')) {
    national = s.slice(3);
  } else if (s.startsWith('0')) {
    national = s.slice(1); // local form: 077... → 77...
  } else {
    national = s; // assume already national (7...)
  }

  // National part must be exactly the 10-digit mobile number starting with 7.
  if (!/^7\d{9}$/.test(national)) return null;

  const e164 = '+964' + national;
  return E164_IRAQI_MOBILE.test(e164) ? e164 : null;
}

export function isValidIraqiPhone(input: string): boolean {
  return normalizeIraqiPhone(input) !== null;
}
