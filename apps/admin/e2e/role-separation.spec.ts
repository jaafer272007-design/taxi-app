import { test, expect, type APIRequestContext } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  SUPER_ADMIN,
  SUPER_ADMIN_STATE,
  apiLogin,
  authHeader,
} from "./fixtures";

/**
 * The one boundary in this panel that is a security control rather than a
 * convenience: only the SUPER_ADMIN may manage admin accounts.
 *
 * Tested at BOTH layers on purpose. Hiding the nav item and redirecting the
 * page are UI decisions — anyone can skip them with a direct HTTP request — so
 * the backend's 403 is the real boundary and gets asserted directly. A suite
 * that only checked the UI would pass just as happily with the guard removed
 * from the API.
 */

const NAV_ITEM = "إدارة المدراء";

/** Accounts created by this spec. The E2E seed deletes anything so prefixed. */
const THROWAWAY_PREFIX = "e2e-throwaway-";

/** Every route the SuperAdminGuard is supposed to be protecting. */
function superAdminRoutes(request: APIRequestContext, token: string, targetId: string) {
  const headers = authHeader(token);
  return [
    { label: "GET /admin/users", send: () => request.get(`${API_URL}/admin/users`, { headers }) },
    {
      label: "POST /admin/users",
      send: () =>
        request.post(`${API_URL}/admin/users`, {
          headers,
          data: { username: `should-never-exist-${Date.now()}`, password: "irrelevant-12345" },
        }),
    },
    {
      label: "PATCH /admin/users/:id",
      send: () =>
        request.patch(`${API_URL}/admin/users/${targetId}`, { headers, data: { active: false } }),
    },
    {
      label: "POST /admin/users/:id/password",
      send: () =>
        request.post(`${API_URL}/admin/users/${targetId}/password`, {
          headers,
          data: { password: "irrelevant-12345" },
        }),
    },
  ];
}

test.describe("a normal ADMIN", () => {
  test.use({ storageState: NORMAL_ADMIN_STATE });

  test("does not see the admin-management nav item", async ({ page }) => {
    await page.goto("/dashboard");

    // The other three nav items must still be there — this is a targeted
    // removal, not a broken sidebar.
    await expect(page.getByRole("link", { name: "لوحة المعلومات" })).toBeVisible();
    await expect(page.getByRole("link", { name: "الممرات والتسعير" })).toBeVisible();
    await expect(page.getByRole("link", { name: "السائقون" })).toBeVisible();
    await expect(page.getByRole("link", { name: NAV_ITEM })).toHaveCount(0);
  });

  test("is redirected away from /admins", async ({ page }) => {
    await page.goto("/admins");

    await expect(page).toHaveURL(/\/dashboard$/);
    // Not just "we ended up elsewhere" — no fragment of the admin-management
    // page may have rendered on the way.
    await expect(page.getByRole("heading", { name: NAV_ITEM })).toHaveCount(0);
    await expect(page.getByText(SUPER_ADMIN.username)).toHaveCount(0);
  });

  test("gets 403 from every /admin/users route", async ({ request }) => {
    const superToken = await apiLogin(request, SUPER_ADMIN);
    const adminToken = await apiLogin(request, NORMAL_ADMIN);

    // A real admin id, so a 404 can never be mistaken for a 403.
    const listed = await request.get(`${API_URL}/admin/users`, {
      headers: authHeader(superToken),
    });
    const targetId = ((await listed.json()) as { id: string }[])[0].id;

    for (const route of superAdminRoutes(request, adminToken, targetId)) {
      const res = await route.send();
      expect(res.status(), `${route.label} must be forbidden for a normal ADMIN`).toBe(403);
    }
  });

  test("keeps every operational permission — the separation is narrow", async ({ request }) => {
    // The failure this guards against is over-correction: locking a normal
    // admin out of the work they exist to do. Corridors, drivers and the
    // dashboard are explicitly shared by both roles.
    const token = await apiLogin(request, NORMAL_ADMIN);
    const headers = authHeader(token);

    for (const path of ["/corridors", "/admin/drivers", "/admin/dashboard"]) {
      const res = await request.get(`${API_URL}${path}`, { headers });
      expect(res.status(), `a normal ADMIN must still be able to GET ${path}`).toBe(200);
    }
  });
});

test.describe("the SUPER_ADMIN", () => {
  test.use({ storageState: SUPER_ADMIN_STATE });

  test("sees the admin-management nav item and can open the page", async ({ page }) => {
    await page.goto("/dashboard");
    await page.getByRole("link", { name: NAV_ITEM }).click();

    await expect(page).toHaveURL(/\/admins$/);
    await expect(page.getByRole("heading", { name: NAV_ITEM })).toBeVisible();
    // The account list actually rendered — the page is not merely reachable.
    await expect(page.getByText(NORMAL_ADMIN.username)).toBeVisible();
  });

  test("is not forbidden from any /admin/users route", async ({ request }) => {
    const token = await apiLogin(request, SUPER_ADMIN);
    const headers = authHeader(token);

    expect((await request.get(`${API_URL}/admin/users`, { headers })).status()).toBe(200);

    // These calls SUCCEED, so they must land on a throwaway. Pointing the
    // password-reset at a fixture account would silently change the credential
    // the rest of the suite logs in with — the failure would surface later as a
    // "broken login" with no hint that this test caused it. The seed cleans up
    // anything with this prefix.
    const created = await request.post(`${API_URL}/admin/users`, {
      headers,
      data: { username: THROWAWAY_PREFIX + Date.now(), password: "throwaway-password-1" },
    });
    expect(created.status(), "the SUPER_ADMIN must be able to create an admin").toBeLessThan(300);
    const target = (await created.json()) as { id: string };

    for (const route of superAdminRoutes(request, token, target.id)) {
      const res = await route.send();
      expect(res.status(), `${route.label} must NOT be forbidden for the SUPER_ADMIN`).not.toBe(
        403,
      );
    }
  });
});
