/**
 * Iraqi (+964) mobile phone handling — client-side mirror of
 * `services/api/src/common/phone.util.ts` (which is authoritative; this only
 * avoids an obviously-invalid round trip to the server before an OTP request).
 */
const E164_IRAQI_MOBILE = /^\+9647\d{9}$/;

export function normalizeIraqiPhone(input: string): string | null {
  if (typeof input !== "string") return null;

  let s = input.trim().replace(/[\s\-().]/g, "");
  if (s.startsWith("00")) s = "+" + s.slice(2);

  let national: string;
  if (s.startsWith("+964")) {
    national = s.slice(4);
  } else if (s.startsWith("964")) {
    national = s.slice(3);
  } else if (s.startsWith("0")) {
    national = s.slice(1);
  } else {
    national = s;
  }

  if (!/^7\d{9}$/.test(national)) return null;

  const e164 = "+964" + national;
  return E164_IRAQI_MOBILE.test(e164) ? e164 : null;
}
