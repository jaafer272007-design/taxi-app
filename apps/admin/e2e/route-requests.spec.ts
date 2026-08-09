import { test, expect } from "@playwright/test";

import { NORMAL_ADMIN_STATE, ROUTE_DEMAND, toArabicDigits } from "./fixtures";

/**
 * Demand for corridors nobody serves, end to end.
 *
 * The point of this screen is a DECISION: which of the 306 corridors do we
 * recruit drivers for this week. Before it, that decision was a guess. So the
 * claims worth testing in a browser are the two the decision rests on —
 * **the ranking is by demand**, and **«طلب بلا عرض» actually removes the served
 * corridors** — and neither is a claim about a function. Both are about a
 * groupBy over real rows, a filter round-tripped through the URL, and a table
 * rendering what came back.
 *
 * The fixture is built so a broken filter cannot pass: it seeds one corridor
 * with demand and NO supply, and one with demand AND a live trip. A filter that
 * did nothing would still show both.
 *
 * Read-only — nothing here mutates state, so it can run in parallel with the
 * rest of the suite.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

const { unserved, served } = ROUTE_DEMAND;

const rowFor = (page: import("@playwright/test").Page, originAr: string, destAr: string) =>
  page.getByRole("row").filter({ hasText: `${originAr} إلى ${destAr}` });

test.describe("route requests", () => {
  test("ranks corridors by demand, highest first", async ({ page }) => {
    await page.goto("/route-requests");

    const unservedRow = rowFor(page, unserved.originAr, unserved.destAr);
    const servedRow = rowFor(page, served.originAr, served.destAr);
    await expect(unservedRow).toHaveCount(1);
    await expect(servedRow).toHaveCount(1);

    // The ranking IS the feature: an admin reads this top-down.
    const [unservedY, servedY] = await Promise.all([
      unservedRow.boundingBox().then((b) => b!.y),
      servedRow.boundingBox().then((b) => b!.y),
    ]);
    expect(unservedY).toBeLessThan(servedY);
  });

  test("separates how many REQUESTS from how many RIDERS", async ({ page }) => {
    await page.goto("/route-requests");

    const row = rowFor(page, unserved.originAr, unserved.destAr);
    // Three requests, two riders — the same rider asked on two days. If these
    // were one number, one determined person would read as a busy route.
    await expect(row).toContainText(toArabicDigits(unserved.requests));
    await expect(row).toContainText(toArabicDigits(unserved.riders));
  });

  test("marks a corridor with no live trips, and shows the supply on one that has them", async ({
    page,
  }) => {
    await page.goto("/route-requests");

    await expect(rowFor(page, unserved.originAr, unserved.destAr)).toContainText("بلا رحلات");
    await expect(rowFor(page, served.originAr, served.destAr)).toContainText(
      `${toArabicDigits(served.activeTrips)} رحلة حيّة`,
    );
  });

  test("«طلب بلا عرض» isolates the actionable list", async ({ page }) => {
    await page.goto("/route-requests");
    await expect(rowFor(page, served.originAr, served.destAr)).toHaveCount(1);

    await page.getByRole("button", { name: "طلب بلا عرض" }).click();
    await page.waitForURL(/unserved=1/);

    // The corridor with demand stays; the one a driver is already serving goes.
    await expect(rowFor(page, unserved.originAr, unserved.destAr)).toHaveCount(1);
    await expect(rowFor(page, served.originAr, served.destAr)).toHaveCount(0);

    // ...and back again, so the filter is a view and not a one-way door.
    await page.getByRole("button", { name: "كل الطلبات" }).click();
    await page.waitForURL((url) => !url.search.includes("unserved"));
    await expect(rowFor(page, served.originAr, served.destAr)).toHaveCount(1);
  });

  test("the filter survives an auto-refresh", async ({ page }) => {
    // The screen re-renders itself every minute. A filter that reset each time
    // would be unusable for the one task this page exists for — which is why it
    // lives in the URL rather than in component state. `?refreshMs=` makes the
    // beat observable in a second instead of sixty.
    await page.goto("/route-requests?unserved=1&refreshMs=1000");
    await expect(rowFor(page, unserved.originAr, unserved.destAr)).toHaveCount(1);

    await page.waitForTimeout(2500);

    await expect(rowFor(page, unserved.originAr, unserved.destAr)).toHaveCount(1);
    await expect(rowFor(page, served.originAr, served.destAr)).toHaveCount(0);
  });

  test("states the window it is counting, rather than leaving it implied", async ({ page }) => {
    await page.goto("/route-requests");
    // A count that silently drops rows after N days is a number nobody can
    // check. The policy value comes from the API, not from a constant here.
    await expect(page.locator("main")).toContainText("تُحتسب الطلبات غير المحقّقة خلال آخر");
  });

  test("is reachable from the sidebar", async ({ page }) => {
    await page.goto("/dashboard");
    await page.getByRole("link", { name: "طلبات المسارات" }).click();
    await page.waitForURL(/route-requests/);
    await expect(page.getByRole("heading", { name: "طلبات المسارات" })).toBeVisible();
  });

  test("renders Arabic city names, never the stored English keys", async ({ page }) => {
    await page.goto("/route-requests");
    const table = page.locator("table");
    await expect(table).toContainText(unserved.originAr);
    // The bug this catches shipped once already, in the support views.
    await expect(table).not.toContainText("Erbil");
    await expect(table).not.toContainText("Basra");
  });
});
