import { test, expect, type APIRequestContext, type Page } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  apiLogin,
  authHeader,
  toWesternDigits,
} from "./fixtures";

/**
 * Auto-refresh, the manual control, and the pending-drivers badge.
 *
 * The panel used to fetch once per navigation, which put an admin in the exact
 * position the rider and driver apps were in: a driver stuck at «بانتظار
 * المراجعة» cannot post a single trip until somebody here sees them, and a list
 * fetched ten minutes ago gives no hint that somebody is waiting.
 *
 * ## Why `?refreshMs=`
 *
 * The production beat is 20 seconds. Proving "it stopped while the tab was
 * hidden" against that would mean a minute of waiting per assertion. The param
 * shortens the beat for THIS TAB ONLY (floored at 1s), so no other spec in the
 * suite has `router.refresh()` firing underneath its clicks — which is exactly
 * what a build-time flag would have caused.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

const FAST = 1_000;

/** The instant of the last completed refresh, as the component recorded it. */
async function lastRefreshedAt(page: Page): Promise<string> {
  return (await page.getByTestId("last-refreshed").getAttribute("dateTime")) ?? "";
}

/** Drive `document.visibilityState` and fire the event the browser would. */
async function setVisibility(page: Page, state: "visible" | "hidden") {
  await page.evaluate((value) => {
    Object.defineProperty(document, "visibilityState", {
      value,
      configurable: true,
    });
    document.dispatchEvent(new Event("visibilitychange"));
  }, state);
}

test("the drivers list refreshes on its own", async ({ page }) => {
  await page.goto(`/drivers?refreshMs=${FAST}`);
  await expect(page.getByRole("heading", { name: "السائقون" })).toBeVisible();

  const first = await lastRefreshedAt(page);
  expect(first).not.toBe("");

  await expect
    .poll(() => lastRefreshedAt(page), { timeout: 10_000 })
    .not.toBe(first);
});

test("the manual control refreshes on demand", async ({ page }) => {
  // No `?refreshMs=`: the beat is the production 20s, so nothing here can be
  // the interval firing — only the button.
  await page.goto("/drivers");
  const before = await lastRefreshedAt(page);

  await page.getByRole("button", { name: "تحديث الآن" }).click();

  await expect.poll(() => lastRefreshedAt(page), { timeout: 10_000 }).not.toBe(before);
  // The rows are still there afterwards — a refresh is not a reload into an
  // empty state.
  await expect(page.locator('[data-slot="card"]').first()).toBeVisible();
});

test("nothing refreshes while the tab is hidden; returning catches up", async ({
  page,
}) => {
  await page.goto(`/drivers?refreshMs=${FAST}`);
  await expect(page.getByRole("heading", { name: "السائقون" })).toBeVisible();

  // Prove it is actually ticking before asserting that it stopped — otherwise
  // "no refresh happened" is vacuously true.
  const start = await lastRefreshedAt(page);
  await expect.poll(() => lastRefreshedAt(page), { timeout: 10_000 }).not.toBe(start);

  await setVisibility(page, "hidden");

  // Let whatever was already on the wire land before taking the baseline.
  // Stopping the beat does not cancel a request that has already been sent —
  // you cannot un-send one — so the timestamp can legitimately advance ONCE
  // after the tab is hidden. Reading the baseline immediately made this test
  // fail in CI by exactly one interval, twice, which looks identical to a
  // leaking timer; on a localhost round trip it never showed.
  await page.waitForTimeout(FAST * 2);
  const whenHidden = await lastRefreshedAt(page);

  // Now the real assertion: four intervals, zero refreshes. A broken gate
  // would land about four here, so this still fails loudly.
  await page.waitForTimeout(FAST * 4);
  expect(
    await lastRefreshedAt(page),
    "the beat kept running with the tab hidden — that is somebody's mobile data",
  ).toBe(whenHidden);

  // Back in view: refresh AT ONCE rather than after another whole interval.
  // Someone returning to a tab is looking at the stalest data they will see.
  await setVisibility(page, "visible");
  await expect.poll(() => lastRefreshedAt(page), { timeout: 5_000 }).not.toBe(whenHidden);
});

test("a failed refresh leaves the table alone and says nothing", async ({ page }) => {
  await page.goto("/drivers");
  const cards = page.locator('[data-slot="card"]');
  const before = await cards.count();
  expect(before).toBeGreaterThan(0);

  // Break exactly one refresh, then get out of the way: what is under test is
  // that the admin is left with their data, not which recovery path Next
  // takes.
  let broken = false;
  await page.route(
    (url) => url.pathname === "/drivers",
    async (route) => {
      if (broken) return route.continue();
      broken = true;
      await route.abort("failed");
    },
  );

  await page.getByRole("button", { name: "تحديث الآن" }).click();
  await page.waitForTimeout(2_000);

  await expect(cards.first()).toBeVisible();
  await expect(cards).toHaveCount(before);
  // Nothing was said about it. (Matching the toast element, not role=alert:
  // sonner's Toaster mounts a permanently-present empty live region, so
  // `getByRole("alert")` is 1 on every page whether or not anything fired.)
  await expect(page.locator("[data-sonner-toast]")).toHaveCount(0);
  await expect(page.getByText("أعد تحميل الصفحة للمحاولة مرة أخرى.")).toHaveCount(0);
  // …and the control is usable again rather than stuck spinning.
  await expect(page.getByRole("button", { name: "تحديث الآن" })).toBeEnabled();

  await page.unroute((url) => url.pathname === "/drivers");
});

/** Drivers awaiting review, straight from the backend. */
async function pendingViaApi(request: APIRequestContext): Promise<number> {
  const token = await apiLogin(request, NORMAL_ADMIN);
  const res = await request.get(`${API_URL}/admin/drivers?status=PENDING`, {
    headers: authHeader(token),
  });
  return ((await res.json()) as unknown[]).length;
}

/** The number the badge is showing, or 0 when it is not drawn at all. */
async function badgeValue(page: Page): Promise<number> {
  const badge = page.getByTestId("pending-drivers-badge");
  if ((await badge.count()) === 0) return 0;
  const digits = ((await badge.textContent()) ?? "").replace(/[^٠-٩]/g, "");
  return digits === "" ? 0 : Number(toWesternDigits(digits));
}

test("the sidebar badge is the number of drivers waiting for review", async ({
  page,
  request,
}) => {
  // Bracketed by two reads of the truth, and asserted only when they agree.
  //
  // `drivers.spec.ts` approves and rejects drivers in the other worker for the
  // whole run, so a page load can legitimately straddle a mutation — the badge
  // comes from the layout's dashboard aggregate and would then be one ahead of
  // a count taken after. Retrying until the count held still across the load
  // keeps the assertion EXACT instead of loosening it to ±1, which would
  // assert nothing at all.
  await expect(async () => {
    const before = await pendingViaApi(request);
    await page.goto("/drivers");
    const shown = await badgeValue(page);
    const after = await pendingViaApi(request);

    expect(before, "a driver was reviewed mid-load — retrying").toBe(after);
    // Zero draws nothing: a badge reading "٠" is a badge saying "look at me,
    // there is nothing here". badgeValue() reports that as 0.
    expect(shown).toBe(before);
  }).toPass({ timeout: 30_000, intervals: [500] });
});

test("the dashboard refreshes on its own too", async ({ page }) => {
  await page.goto(`/dashboard?refreshMs=${FAST}`);
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();

  const first = await lastRefreshedAt(page);
  await expect.poll(() => lastRefreshedAt(page), { timeout: 10_000 }).not.toBe(first);
});

test("the corridors list is deliberately NOT auto-refreshed", async ({ page }) => {
  // 306 rows that only ever change when an admin changes them, and the admin
  // who changed them is already looking at the result of their own action.
  // A refresh control here would be a re-fetch of the whole grid every minute
  // for nothing.
  await page.goto("/corridors");
  await expect(page.getByRole("heading", { name: /الممرات/ })).toBeVisible();
  await expect(page.getByTestId("last-refreshed")).toHaveCount(0);
});
