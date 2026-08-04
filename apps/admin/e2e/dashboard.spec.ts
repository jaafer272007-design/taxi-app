import { test, expect } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  apiLogin,
  authHeader,
  formatIqd,
  toArabicDigits,
} from "./fixtures";

/**
 * Dashboard integrity.
 *
 * This screen shipped once rendering `NaN` where a counter should have been —
 * caught by eye during a manual browser check on PR #28, which is precisely the
 * kind of check that does not run again. The assertions below are written to
 * fail on that exact bug, and on its two neighbours: a missing value silently
 * showing as broken arithmetic, and an unmapped status key leaking the English
 * enum onto an Arabic screen.
 *
 * The lesson from #28 was that a loose assertion is worse than none, because it
 * looks like coverage. So rather than checking "some digits appeared", each
 * counter is compared against what the API actually returns, converted
 * independently.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

interface DashboardCounts {
  riders?: number;
  drivers?: { total?: number; byStatus?: Record<string, number> };
  trips?: { total?: number; byStatus?: Record<string, number>; today?: number };
  bookings?: number;
  earningsTotal?: number;
}

/** Arabic labels the panel maps every known status to. */
const DRIVER_STATUS_LABELS: Record<string, string> = {
  PENDING: "بانتظار المراجعة",
  APPROVED: "معتمدون",
  REJECTED: "مرفوضون",
  SUSPENDED: "موقوفون",
};

const TRIP_STATUS_LABELS: Record<string, string> = {
  OPEN: "مفتوحة",
  LOCKED: "مكتملة الحجز",
  EN_ROUTE: "جارية",
  COMPLETED: "منتهية",
  SETTLED: "مسوّاة",
  CANCELLED: "ملغاة",
};

/**
 * The whole card carrying a given title.
 *
 * Locating by title text alone lands on the title element itself, which holds
 * the label and NOT the value — an assertion against it can never pass, and an
 * assertion for absence against it would always pass. `data-slot="card"` is the
 * component's own hook for the outer element.
 */
function cardWithTitle(page: import("@playwright/test").Page, title: string) {
  return page
    .locator('[data-slot="card"]')
    .filter({ has: page.getByText(title, { exact: true }) });
}

test("every counter renders the API's real number, in Arabic-Indic digits", async ({
  page,
  request,
}) => {
  const token = await apiLogin(request, NORMAL_ADMIN);
  const res = await request.get(`${API_URL}/admin/dashboard`, { headers: authHeader(token) });
  const counts = (await res.json()) as DashboardCounts;

  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();

  // Each stat card is located by its label, then its value is compared to the
  // API's own answer. Comparing against the live payload rather than a
  // hardcoded number keeps this correct no matter which mutating specs have
  // already run — the counts move, the relationship does not.
  const card = (label: string) => cardWithTitle(page, label);

  await expect(card("الركّاب")).toContainText(toArabicDigits(counts.riders!));
  await expect(card("السائقون")).toContainText(toArabicDigits(counts.drivers!.total!));
  await expect(card("الرحلات")).toContainText(toArabicDigits(counts.trips!.total!));
  await expect(card("الحجوزات")).toContainText(toArabicDigits(counts.bookings!));

  // Money gets the thousands separator and the dinar suffix.
  await expect(page.getByText("إجمالي النقد المحصّل")).toBeVisible();
  await expect(page.getByText(`${formatIqd(counts.earningsTotal!)} د.ع`)).toBeVisible();
});

test('no "NaN" anywhere on the page — the PR #28 regression', async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();

  const body = await page.locator("body").innerText();
  expect(body, "the dashboard is rendering NaN where a number belongs").not.toContain("NaN");
  // `undefined` and `null` reaching the DOM are the same bug one step earlier.
  expect(body).not.toContain("undefined");
  expect(body).not.toContain("null");
});

test("no raw English enum key is rendered instead of an Arabic label", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();

  const body = await page.locator("body").innerText();
  for (const key of [...Object.keys(DRIVER_STATUS_LABELS), ...Object.keys(TRIP_STATUS_LABELS)]) {
    expect(body, `the dashboard is showing the raw key "${key}" instead of its Arabic label`).not.toContain(
      key,
    );
  }
});

test("the per-status breakdown labels every status the backend sent", async ({ page, request }) => {
  const token = await apiLogin(request, NORMAL_ADMIN);
  const res = await request.get(`${API_URL}/admin/dashboard`, { headers: authHeader(token) });
  const counts = (await res.json()) as DashboardCounts;

  await page.goto("/dashboard");

  // Emptiness would make the two assertions below vacuous: with no statuses to
  // render, "every status is labelled" is true and proves nothing. The seed
  // guarantees drivers in several states.
  const byStatus = counts.drivers?.byStatus ?? {};
  expect(Object.keys(byStatus).length, "no driver statuses to check — is the E2E seed applied?")
    .toBeGreaterThan(0);

  await expect(page.getByRole("heading", { name: "السائقون حسب الحالة" })).toBeVisible();
  for (const [status, value] of Object.entries(byStatus)) {
    const label = DRIVER_STATUS_LABELS[status];
    expect(label, `the panel has no Arabic label for driver status "${status}"`).toBeDefined();
    await expect(cardWithTitle(page, label)).toContainText(toArabicDigits(value));
  }
});

test("all digits on the page are Arabic-Indic — the locked display rule", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "لوحة المعلومات" })).toBeVisible();

  // Scoped to <main>: the sidebar shows the signed-in USERNAME, and a username
  // is an identifier, not a display value — "e2e-admin" is spelled with a
  // Western 2 and always will be. Inside the content area every number is a
  // counter or an amount, so a Western digit there means a value bypassed the
  // formatters.
  const content = await page.locator("main").innerText();
  expect(
    content,
    "a Western digit reached the dashboard — display values must be Arabic-Indic",
  ).not.toMatch(/[0-9]/);
});
