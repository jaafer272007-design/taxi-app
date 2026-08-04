import { test, expect } from "@playwright/test";

import {
  DISABLED_ADMIN,
  GENERIC_LOGIN_FAILURE,
  LOCKOUT_ADMIN,
  LOGIN_RATE_LIMIT_MAX,
  NORMAL_ADMIN,
  RATE_LIMITED_MESSAGE,
  WRONGPASS_ADMIN,
} from "./fixtures";

/**
 * The login form, driven as a person drives it.
 *
 * Runs with NO stored session — this is the one spec that must not inherit the
 * cookies `auth.setup.ts` cached, since signing in is the thing under test.
 */
test.use({ storageState: { cookies: [], origins: [] } });

/**
 * Serial, because these tests share the login throttle. It keys on
 * username+IP, and every worker here presents the same IP, so two failing
 * logins running concurrently would spend one budget between them.
 */
test.describe.configure({ mode: "serial" });

/**
 * The form's error message.
 *
 * NOT `getByRole("alert")`: Next renders its own route announcer as
 * `<div role="alert" id="__next-route-announcer__">`, which is always present
 * and almost always empty, so the role selector resolves to it and every
 * assertion against the real message times out against an empty string.
 */
function loginError(page: import("@playwright/test").Page) {
  return page.locator('p[role="alert"]');
}

async function attemptLogin(
  page: import("@playwright/test").Page,
  username: string,
  password: string,
) {
  await page.goto("/login");
  await page.getByLabel("اسم المستخدم").fill(username);
  await page.getByLabel("كلمة المرور").fill(password);
  await page.getByRole("button", { name: "دخول" }).click();
}

test("correct credentials reach the dashboard", async ({ page }) => {
  await attemptLogin(page, NORMAL_ADMIN.username, NORMAL_ADMIN.password);

  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();
  // The signed-in identity is rendered from GET /admin/auth/me, so seeing the
  // username proves the session cookie was set AND that the backend accepted it.
  await expect(page.getByText(NORMAL_ADMIN.username)).toBeVisible();
});

test("a wrong password fails with the generic message and stays on /login", async ({ page }) => {
  await attemptLogin(page, WRONGPASS_ADMIN.username, "definitely-not-the-password");

  await expect(loginError(page)).toHaveText(GENERIC_LOGIN_FAILURE);
  await expect(page).toHaveURL(/\/login$/);
});

test("an unknown username fails with the SAME message — no account enumeration", async ({
  page,
}) => {
  // The point of this pair of tests is the word "same". If these two ever
  // diverge, an attacker can sort real usernames from invented ones without
  // guessing a single password, which is the expensive half of the problem
  // handed to them for free.
  await attemptLogin(page, "no-such-admin-anywhere", "definitely-not-the-password");

  await expect(loginError(page)).toHaveText(GENERIC_LOGIN_FAILURE);
  await expect(page).toHaveURL(/\/login$/);
});

test("a disabled account fails with the SAME message, even with the right password", async ({
  page,
}) => {
  // "This account exists but is disabled" is the same leak by a different
  // route — and it is the easiest one to reintroduce, because it reads like a
  // helpful error.
  await attemptLogin(page, DISABLED_ADMIN.username, DISABLED_ADMIN.password);

  await expect(loginError(page)).toHaveText(GENERIC_LOGIN_FAILURE);
  await expect(page).toHaveURL(/\/login$/);
});

test(`the rate limiter blocks after ${LOGIN_RATE_LIMIT_MAX} failures`, async ({ page }) => {
  // Uses its own account: the throttle counter is per username+IP, and burning
  // a shared account's budget here would lock other specs out.
  for (let attempt = 1; attempt <= LOGIN_RATE_LIMIT_MAX; attempt++) {
    await attemptLogin(page, LOCKOUT_ADMIN.username, `wrong-password-${attempt}`);
    await expect(
      loginError(page),
      `attempt ${attempt} of ${LOGIN_RATE_LIMIT_MAX} should still be the generic failure`,
    ).toHaveText(GENERIC_LOGIN_FAILURE);
  }

  // Budget spent: the next attempt is refused before the password is even
  // considered, and says so differently.
  await attemptLogin(page, LOCKOUT_ADMIN.username, `wrong-password-${LOGIN_RATE_LIMIT_MAX + 1}`);
  await expect(loginError(page)).toHaveText(RATE_LIMITED_MESSAGE);

  // And the lockout is not a password check in disguise — the CORRECT password
  // is refused too while the window is open. If this ever starts letting the
  // right password through, the limiter has stopped being a brute-force
  // defence.
  await attemptLogin(page, LOCKOUT_ADMIN.username, LOCKOUT_ADMIN.password);
  await expect(loginError(page)).toHaveText(RATE_LIMITED_MESSAGE);
  await expect(page).toHaveURL(/\/login$/);
});

test("a signed-out browser is redirected off the panel", async ({ page }) => {
  await page.goto("/corridors");
  await expect(page).toHaveURL(/\/login$/);
});
