import { test, expect, type APIRequestContext } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  DRIVERS,
  DRIVER_STATUS_AR,
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  apiLogin,
  authHeader,
} from "./fixtures";

/**
 * Driver approval — the panel's other operationally important job. An approved
 * driver can post trips; a rejected one is told why.
 *
 * Every action is verified against the DATABASE as well as the screen. A toast
 * saying "تم اعتماد السائق" while the row never changed status is exactly the
 * kind of failure a screen-only assertion waves through.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

async function statusOf(request: APIRequestContext, phone: string): Promise<string | undefined> {
  const token = await apiLogin(request, NORMAL_ADMIN);
  const res = await request.get(`${API_URL}/admin/drivers`, { headers: authHeader(token) });
  const drivers = (await res.json()) as {
    status: string;
    rejectionReason: string | null;
    user: { phone: string } | null;
  }[];
  return drivers.find((d) => d.user?.phone === phone)?.status;
}

/**
 * The card for one driver, located by the name the seed gave them.
 *
 * `data-slot="card"` is the component's own hook for the outer element.
 * Filtering plain `div`s by text instead lands on the innermost matching node —
 * the title — which holds the name and none of the buttons or the status badge.
 */
function cardFor(page: import("@playwright/test").Page, name: string) {
  return page.locator('[data-slot="card"]').filter({ hasText: name });
}

test("the status filter narrows the list to that status", async ({ page }) => {
  // Asserted with the two drivers no test ever mutates, so this holds
  // regardless of what has already run — including on a CI retry.
  await page.goto("/drivers?status=REJECTED");
  await expect(page.getByText(DRIVERS.rejected.name)).toBeVisible();
  await expect(page.getByText(DRIVERS.stable.name)).toHaveCount(0);

  await page.goto("/drivers?status=PENDING");
  await expect(page.getByText(DRIVERS.stable.name)).toBeVisible();
  await expect(page.getByText(DRIVERS.rejected.name)).toHaveCount(0);

  // Unfiltered shows both.
  await page.goto("/drivers");
  await expect(page.getByText(DRIVERS.stable.name)).toBeVisible();
  await expect(page.getByText(DRIVERS.rejected.name)).toBeVisible();
});

test("a rejected driver's reason is shown to the admin", async ({ page }) => {
  await page.goto("/drivers?status=REJECTED");
  await expect(page.getByText("سبب الرفض:")).toBeVisible();
  await expect(page.getByText("صورة إجازة السوق غير واضحة.")).toBeVisible();
});

test("approving actually moves the driver to APPROVED", async ({ page, request }) => {
  expect(await statusOf(request, DRIVERS.approve.phone)).toBe("PENDING");

  await page.goto("/drivers?status=PENDING");
  await cardFor(page, DRIVERS.approve.name).getByRole("button", { name: "اعتماد" }).click();
  await expect(page.getByText("تم اعتماد السائق.")).toBeVisible();

  expect(
    await statusOf(request, DRIVERS.approve.phone),
    "the toast appeared but the driver never changed status",
  ).toBe("APPROVED");

  // And the panel agrees on a fresh load.
  await page.goto("/drivers?status=APPROVED");
  await expect(page.getByText(DRIVERS.approve.name)).toBeVisible();
  await expect(cardFor(page, DRIVERS.approve.name)).toContainText(DRIVER_STATUS_AR.APPROVED);
});

test("rejecting records the reason the admin typed", async ({ page, request }) => {
  const reason = "صورة الهوية غير مقروءة.";
  expect(await statusOf(request, DRIVERS.reject.phone)).toBe("PENDING");

  await page.goto("/drivers?status=PENDING");
  await cardFor(page, DRIVERS.reject.name).getByRole("button", { name: "رفض" }).click();

  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await dialog.getByLabel("سبب الرفض").fill(reason);
  await dialog.getByRole("button", { name: "رفض الطلب" }).click();

  await expect(page.getByText("تم رفض الطلب وإشعار السائق بالسبب.")).toBeVisible();
  expect(await statusOf(request, DRIVERS.reject.phone)).toBe("REJECTED");

  // The reason is what the driver sees in their app, so it has to be the text
  // that was actually typed — not a placeholder or an empty string.
  await page.goto("/drivers?status=REJECTED");
  await expect(cardFor(page, DRIVERS.reject.name)).toContainText(reason);
});

test("suspending an approved driver moves them to SUSPENDED", async ({ page, request }) => {
  expect(await statusOf(request, DRIVERS.suspend.phone)).toBe("APPROVED");

  await page.goto("/drivers?status=APPROVED");
  await cardFor(page, DRIVERS.suspend.name).getByRole("button", { name: "إيقاف" }).click();
  await expect(page.getByText("تم إيقاف السائق.")).toBeVisible();

  expect(await statusOf(request, DRIVERS.suspend.phone)).toBe("SUSPENDED");

  await page.goto("/drivers?status=SUSPENDED");
  await expect(cardFor(page, DRIVERS.suspend.name)).toContainText(DRIVER_STATUS_AR.SUSPENDED);
});

test("no raw English status leaks onto the drivers page", async ({ page }) => {
  await page.goto("/drivers");
  const body = await page.locator("body").innerText();

  for (const status of Object.keys(DRIVER_STATUS_AR)) {
    expect(body, `the raw status "${status}" is showing instead of its Arabic label`).not.toContain(
      status,
    );
  }
});
