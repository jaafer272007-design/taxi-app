import { test, expect } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  NORMAL_ADMIN,
  SUPER_ADMIN,
  SUPER_ADMIN_STATE,
  apiLogin,
  authHeader,
} from "./fixtures";

/**
 * The password hash must never leave the server.
 *
 * `AdminAccount` in `src/lib/types.ts` has no `passwordHash` field, which makes
 * it a compile-time fact for code that goes through that type — but a hash
 * could still arrive in a payload and be rendered by something that spreads an
 * object, or be embedded in the RSC stream that Next ships to the browser.
 * These check the bytes that actually reach the client.
 */

/** bcrypt's own prefix — `$2a$`, `$2b$` or `$2y$` followed by the cost. */
const BCRYPT_PATTERN = /\$2[aby]\$\d{2}\$/;

test.describe("no password hash reaches the client", () => {
  test.use({ storageState: SUPER_ADMIN_STATE });

  // /admins is the page that lists admin accounts, so it is the one with a hash
  // anywhere near it. The others are checked because a leak via a shared layout
  // or a stray fetch would not respect that reasoning.
  for (const path of ["/admins", "/dashboard", "/corridors", "/drivers"]) {
    test(`${path} contains no bcrypt hash`, async ({ page }) => {
      const response = await page.goto(path);
      expect(response?.ok(), `${path} did not load`).toBeTruthy();

      // The full server response, not the rendered text: Next serialises server
      // data into the RSC payload inside the HTML, where it is invisible on
      // screen but perfectly readable in devtools.
      const html = await page.content();
      expect(html, `a bcrypt hash is present in the HTML of ${path}`).not.toMatch(BCRYPT_PATTERN);
      expect(html.toLowerCase(), `"passwordHash" appears in the HTML of ${path}`).not.toContain(
        "passwordhash",
      );
    });
  }
});

test("the panel's own login response carries no hash and no token", async ({ request }) => {
  const res = await request.post("/api/auth/login", {
    data: { username: NORMAL_ADMIN.username, password: NORMAL_ADMIN.password },
  });
  expect(res.ok()).toBeTruthy();

  const body = await res.text();
  expect(body).not.toMatch(BCRYPT_PATTERN);
  expect(body.toLowerCase()).not.toContain("passwordhash");
  // The JWT belongs in the httpOnly cookie only — if it is also in the body,
  // any script on the page can read it, which is the whole reason the login
  // goes through a Route Handler rather than a Server Action.
  expect(body).not.toContain("accessToken");
  expect(JSON.parse(body)).toEqual({ role: "ADMIN" });
});

test("the backend's admin endpoints never serialise a hash", async ({ request }) => {
  const token = await apiLogin(request, SUPER_ADMIN);
  const headers = authHeader(token);

  // /admin/users is the only endpoint that reads the AdminUser table, so it is
  // where a `select`-less Prisma query would leak every hash at once.
  for (const path of ["/admin/users", "/admin/auth/me", "/admin/drivers"]) {
    const res = await request.get(`${API_URL}${path}`, { headers });
    const body = await res.text();
    expect(body, `${path} returned a bcrypt hash`).not.toMatch(BCRYPT_PATTERN);
    expect(body.toLowerCase(), `${path} returned a passwordHash field`).not.toContain(
      "passwordhash",
    );
  }
});

test("the session cookie is httpOnly, so scripts cannot read it", async ({ page, context }) => {
  await page.goto("/login");
  await page.getByLabel("اسم المستخدم").fill(NORMAL_ADMIN.username);
  await page.getByLabel("كلمة المرور").fill(NORMAL_ADMIN.password);
  await page.getByRole("button", { name: "دخول" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);

  const cookie = (await context.cookies()).find((c) => c.name === "admin_token");
  expect(cookie, "no session cookie was set").toBeDefined();
  expect(cookie!.httpOnly, "the session cookie must be httpOnly").toBe(true);

  // The definitive check: what JavaScript on the page can actually see.
  const visibleToScripts = await page.evaluate(() => document.cookie);
  expect(visibleToScripts).not.toContain("admin_token");
});
