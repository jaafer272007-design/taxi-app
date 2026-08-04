import { expect, type APIRequestContext } from "@playwright/test";

import { API_URL, STORAGE_STATE_DIR } from "../playwright.config";

/**
 * Cached signed-in browser states, written by `auth.setup.ts`.
 *
 * They live here rather than in the setup file because Playwright refuses to
 * let one test file import another, and `auth.setup.ts` is a test file.
 */
export const SUPER_ADMIN_STATE = `${STORAGE_STATE_DIR}/super-admin.json`;
export const NORMAL_ADMIN_STATE = `${STORAGE_STATE_DIR}/admin.json`;

/**
 * The state `services/api/prisma/seed-e2e.ts` guarantees.
 *
 * The two files live in different packages with different toolchains, so the
 * values are written out in both rather than imported across the boundary. That
 * duplication is only safe because it is *checked*: `seed-contract.spec.ts`
 * asserts every value here against the running API and names the seed file when
 * it doesn't match, so drift fails loudly on the next run instead of silently
 * making some other test assert the wrong thing.
 */

/** Every seeded account shares this password. Test-only. */
export const E2E_PASSWORD = "e2e-password-1234";

export const SUPER_ADMIN = {
  username: process.env.SUPER_ADMIN_USERNAME ?? "e2e-superadmin",
  password: process.env.SUPER_ADMIN_PASSWORD ?? E2E_PASSWORD,
};

/** A normal ADMIN: full operational rights, no admin-account management. */
export const NORMAL_ADMIN = { username: "e2e-admin", password: E2E_PASSWORD };

/** Spends its five attempts in the rate-limit test — used by nothing else. */
export const LOCKOUT_ADMIN = { username: "e2e-lockout", password: E2E_PASSWORD };

/** Receives exactly one wrong-password attempt. */
export const WRONGPASS_ADMIN = { username: "e2e-wrongpass", password: E2E_PASSWORD };

/** Exists, correct password, but `active: false` — must fail like the rest. */
export const DISABLED_ADMIN = { username: "e2e-disabled", password: E2E_PASSWORD };

/** The messages the backend is contractually required to return. */
export const GENERIC_LOGIN_FAILURE = "اسم المستخدم أو كلمة المرور غير صحيحة.";
export const RATE_LIMITED_MESSAGE = "محاولات دخول كثيرة. انتظر قليلاً ثم حاول مرة أخرى.";
export const DUPLICATE_CORRIDOR_MESSAGE = "يوجد ممر لهذا المسار مسبقاً.";

/** How many failures the throttle allows before locking the pair out. */
export const LOGIN_RATE_LIMIT_MAX = Number(process.env.ADMIN_LOGIN_RATE_LIMIT_MAX ?? 5);

/**
 * Pairs the seed deletes so the panel can create them. The production grid
 * fills all 306 ordered pairs, so without this there is no free pair left and
 * "create a corridor" could only ever produce a duplicate error.
 */
export const FREE_CORRIDOR = { origin: "Duhok", originAr: "دهوك", dest: "Samawah", destAr: "السماوة" };

/** A pair that definitely EXISTS — used to prove duplicates are rejected. */
export const EXISTING_CORRIDOR = { origin: "Najaf", originAr: "النجف", dest: "Karbala", destAr: "كربلاء" };

/** Reserved for the "edit a price" test so no other test observes the change. */
export const EDITABLE_CORRIDOR = {
  origin: "Tikrit",
  originAr: "تكريت",
  dest: "Amarah",
  destAr: "العمارة",
  suggested: 30000,
};

/** Reserved for the "toggle active" test. Seeded active. */
export const TOGGLEABLE_CORRIDOR = {
  origin: "Amarah",
  originAr: "العمارة",
  dest: "Tikrit",
  destAr: "تكريت",
};

/** Corridors present after seeding: the full 306-pair grid minus the two freed. */
export const SEEDED_CORRIDOR_COUNT = 304;

/** Every city appears as origin in 17 corridors and as destination in 17. */
export const CORRIDORS_PER_CITY = 34;

export const DRIVERS = {
  approve: { phone: "+9647999000001", name: "سائق الاعتماد", status: "PENDING" },
  reject: { phone: "+9647999000002", name: "سائق الرفض", status: "PENDING" },
  suspend: { phone: "+9647999000003", name: "سائق الإيقاف", status: "APPROVED" },
  /** Never mutated — safe for status-filter assertions and for retries. */
  rejected: { phone: "+9647999000004", name: "سائق مرفوض", status: "REJECTED" },
  /** Never mutated. */
  stable: { phone: "+9647999000005", name: "سائق ثابت للفلترة", status: "PENDING" },
} as const;

/** Drivers the seed creates. Used to assert totals that must not drift. */
export const SEEDED_DRIVER_COUNT = 5;

/** Status labels the panel renders. A raw English status on screen is a bug. */
export const DRIVER_STATUS_AR: Record<string, string> = {
  PENDING: "بانتظار المراجعة",
  APPROVED: "معتمد",
  SUSPENDED: "موقوف",
  REJECTED: "مرفوض",
};

// ── Helpers ──────────────────────────────────────────────────────────────

const WESTERN_ZERO = 0x30;
const ARABIC_ZERO = 0x0660;

/**
 * Western digits → Arabic-Indic, mirroring `src/lib/format.ts`.
 *
 * Reimplemented here rather than imported so the tests assert against an
 * INDEPENDENT conversion. Importing the app's own helper would make a test that
 * passes even if that helper started returning Western digits — it would be
 * comparing the code to itself.
 */
export function toArabicDigits(input: string | number): string {
  let out = "";
  for (const ch of String(input)) {
    const code = ch.codePointAt(0)!;
    out +=
      code >= WESTERN_ZERO && code <= WESTERN_ZERO + 9
        ? String.fromCodePoint(ARABIC_ZERO + (code - WESTERN_ZERO))
        : ch;
  }
  return out;
}

/** `12000` → `١٢٬٠٠٠`, with the Arabic thousands separator U+066C. */
export function formatIqd(amount: number): string {
  const digits = Math.abs(Math.trunc(amount)).toString();
  let grouped = "";
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) grouped += "٬";
    grouped += digits[i];
  }
  return toArabicDigits(`${amount < 0 ? "-" : ""}${grouped}`);
}

/** Logs straight into the BACKEND, bypassing the panel, and returns the JWT. */
export async function apiLogin(
  request: APIRequestContext,
  credentials: { username: string; password: string },
): Promise<string> {
  const res = await request.post(`${API_URL}/admin/auth/login`, {
    data: credentials,
  });
  expect(
    res.ok(),
    `backend login failed for ${credentials.username} — is the E2E seed applied? ` +
      `(services/api/prisma/seed-e2e.ts)`,
  ).toBeTruthy();
  return (await res.json()).accessToken as string;
}

export function authHeader(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}
