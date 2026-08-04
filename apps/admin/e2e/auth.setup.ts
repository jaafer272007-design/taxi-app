import { test as setup, expect } from "@playwright/test";

import {
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  SUPER_ADMIN,
  SUPER_ADMIN_STATE,
} from "./fixtures";

/**
 * Signs in once per role and caches the session cookie, so the other specs
 * start already authenticated instead of driving the login form 30 times.
 *
 * This deliberately goes through the real UI rather than writing a cookie
 * directly: if login breaks, every spec that depends on it should fail here
 * with one obvious message rather than 30 confusing ones. The login flow's own
 * assertions live in `login.spec.ts`, which runs with no stored session.
 */

async function signIn(
  page: import("@playwright/test").Page,
  credentials: { username: string; password: string },
  statePath: string,
) {
  await page.goto("/login");
  await page.getByLabel("اسم المستخدم").fill(credentials.username);
  await page.getByLabel("كلمة المرور").fill(credentials.password);
  await page.getByRole("button", { name: "دخول" }).click();

  // Landing on the dashboard is the proof the cookie was accepted — a Secure
  // cookie that the browser refused would leave us back on /login.
  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();

  await page.context().storageState({ path: statePath });
}

setup("authenticate as super admin", async ({ page }) => {
  await signIn(page, SUPER_ADMIN, SUPER_ADMIN_STATE);
});

setup("authenticate as normal admin", async ({ page }) => {
  await signIn(page, NORMAL_ADMIN, NORMAL_ADMIN_STATE);
});
