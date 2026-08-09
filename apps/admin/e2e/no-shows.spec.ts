import { test, expect } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  NO_SHOW_POLICY,
  NO_SHOW_RIDER,
  apiLogin,
  authHeader,
  toArabicDigits,
} from "./fixtures";

/**
 * The appeal desk, end to end.
 *
 * The automatic block is deliberately blunt — three no-shows in a month and a
 * rider cannot book for a week — and that is only defensible because an admin
 * can undo it. A genuine emergency must not be indistinguishable from someone
 * who simply does not turn up. So the thing worth testing is not "the void
 * endpoint returns 200": it is that an admin clicking «ألغِ الواقعة» in a
 * browser actually **unblocks the rider**, which is a claim about the panel,
 * the server action, the API and the policy query all agreeing.
 *
 * Unit tests cannot make that claim. `NoShowService.void` is one `updateMany`;
 * whether the count that gates booking then falls below the threshold is a
 * question about a query over real rows, which is why the assertion at the end
 * re-reads the blocked list from the API rather than trusting the page.
 *
 * ## Serial, and it mutates
 *
 * These tests share one seeded rider and the second one voids a record, so they
 * run in order. Nothing else in the suite touches no-show state; the seed
 * rebuilds the rider from scratch on every run.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

test.describe.configure({ mode: "serial" });

test.describe("no-shows", () => {
  test("the blocked rider is listed with the policy that blocked them", async ({ page }) => {
    await page.goto("/no-shows");

    // The policy is stated on the page, not just enforced in a config file: an
    // admin deciding whether to void a record needs to know what the threshold
    // was.
    const header = page.locator("main");
    await expect(header).toContainText(toArabicDigits(NO_SHOW_POLICY.threshold));
    await expect(header).toContainText(toArabicDigits(NO_SHOW_POLICY.windowDays));

    const row = page.getByRole("row").filter({ hasText: NO_SHOW_RIDER.name });
    await expect(row).toHaveCount(1);
    // The phone is an identifier to dial, so it stays Western and LTR — the
    // documented exception to the Arabic-Indic rule (CLAUDE.md).
    await expect(row).toContainText(NO_SHOW_RIDER.phone);
    await expect(row).toContainText(toArabicDigits(NO_SHOW_RIDER.occurrences));
  });

  test("opening the history shows every occurrence, all counted", async ({ page }) => {
    await page.goto("/no-shows");
    await page
      .getByRole("row")
      .filter({ hasText: NO_SHOW_RIDER.name })
      .getByRole("button", { name: "السجل" })
      .click();

    await expect(page.getByRole("heading", { name: "سجل الراكب" })).toBeVisible();
    await expect(page.getByText("موقوف حتى")).toBeVisible();
    await expect(page.getByRole("button", { name: "ألغِ الواقعة" })).toHaveCount(
      NO_SHOW_RIDER.occurrences,
    );
  });

  test("a reason is required before a record can be voided", async ({ page }) => {
    await page.goto("/no-shows");
    await page
      .getByRole("row")
      .filter({ hasText: NO_SHOW_RIDER.name })
      .getByRole("button", { name: "السجل" })
      .click();
    await page.getByRole("button", { name: "ألغِ الواقعة" }).first().click();

    // Undoing a penalty with no written reason cannot be reviewed later, and
    // teaches the policy nothing about the cases it got wrong. So the confirm
    // button stays disabled until something is typed.
    const confirm = page.getByRole("button", { name: "تأكيد" });
    await expect(confirm).toBeDisabled();
    await page.getByLabel("السبب (مطلوب)").fill("مر");
    await expect(confirm).toBeDisabled();
  });

  test("voiding one record drops the rider below the threshold and unblocks them", async ({
    page,
    request,
  }) => {
    await page.goto("/no-shows");
    await page
      .getByRole("row")
      .filter({ hasText: NO_SHOW_RIDER.name })
      .getByRole("button", { name: "السجل" })
      .click();

    const reason = "ظرف طارئ — مراجعة مستشفى";
    await page.getByRole("button", { name: "ألغِ الواقعة" }).first().click();
    await page.getByLabel("السبب (مطلوب)").fill(reason);
    await page.getByRole("button", { name: "تأكيد" }).click();

    // The badge flips because the count is now below the threshold — this is the
    // whole appeal in one assertion.
    await expect(page.getByText("غير موقوف")).toBeVisible();
    // The voided row stays, with its reason: that is the audit trail. Hiding it
    // would leave no trace that anyone reviewed the case at all.
    await expect(page.getByText("ملغاة")).toBeVisible();
    await expect(page.getByText(reason)).toBeVisible();
    await expect(page.getByRole("button", { name: "ألغِ الواقعة" })).toHaveCount(
      NO_SHOW_RIDER.occurrences - 1,
    );

    // And the list the block is actually read from no longer holds them. Asked
    // of the API, not the page: the page could be showing a stale render, and
    // this is the value that decides whether POST /bookings returns 403.
    const token = await apiLogin(request, NORMAL_ADMIN);
    const res = await request.get(`${API_URL}/admin/no-shows/blocked`, {
      headers: authHeader(token),
    });
    const { riders } = (await res.json()) as { riders: { phone: string | null }[] };
    expect(riders.some((r) => r.phone === NO_SHOW_RIDER.phone)).toBe(false);
  });
});
