import { test, expect, type Page } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  CORRIDORS_PER_CITY,
  DUPLICATE_CORRIDOR_MESSAGE,
  EDITABLE_CORRIDOR,
  EXISTING_CORRIDOR,
  FREE_CORRIDOR,
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  TOGGLEABLE_CORRIDOR,
  apiLogin,
  authHeader,
  formatIqd,
  toArabicDigits,
} from "./fixtures";

/**
 * Corridors: the screen that decides what a driver may charge.
 *
 * Corridor management is open to both admin roles, so this runs as the NORMAL
 * admin — which also keeps a regression that accidentally made corridors
 * super-admin-only from passing unnoticed.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

/** A page size of 25 is the panel's own constant; the pagination depends on it. */
const PAGE_SIZE = 25;

/** Reads corridors straight from the API — the truth the UI is claiming to show. */
async function fetchCorridors(request: import("@playwright/test").APIRequestContext) {
  const token = await apiLogin(request, NORMAL_ADMIN);
  const res = await request.get(`${API_URL}/corridors`, { headers: authHeader(token) });
  return (await res.json()) as {
    id: string;
    originCity: string;
    destCity: string;
    active: boolean;
    suggestedPricePerSeat: number;
    minPricePerSeat: number;
    maxPricePerSeat: number;
  }[];
}

async function openCreateDialog(page: Page) {
  await page.goto("/corridors");
  await page.getByRole("button", { name: "أنشئ ممراً جديداً" }).first().click();
  await expect(page.getByRole("dialog")).toBeVisible();
}

async function selectCity(page: Page, field: "من" | "إلى", cityAr: string) {
  // The dialog's two comboboxes are in DOM order: origin, then destination.
  const combos = page.getByRole("dialog").getByRole("combobox");
  await combos.nth(field === "من" ? 0 : 1).click();
  // Radix renders the options in a portal outside the dialog, so this looks at
  // the page rather than the dialog.
  await page.getByRole("option", { name: cityAr, exact: true }).click();
}

/**
 * Narrow the list to ONE corridor using the origin/destination filters.
 *
 * Free-text search cannot do this: it matches either endpoint, so searching
 * "تكريت" and then picking the row containing "العمارة" finds Tikrit→Amarah AND
 * Amarah→Tikrit. Both directions are separate rows with separate prices, and
 * editing the wrong one would still look green.
 */
async function filterToPair(page: Page, originAr: string, destAr: string) {
  await page.goto("/corridors");
  await page.getByRole("combobox", { name: "تصفية حسب مدينة الانطلاق" }).click();
  await page.getByRole("option", { name: `من: ${originAr}`, exact: true }).click();
  await page.getByRole("combobox", { name: "تصفية حسب مدينة الوصول" }).click();
  await page.getByRole("option", { name: `إلى: ${destAr}`, exact: true }).click();

  const row = page.locator("tbody tr");
  await expect(row, `expected exactly one ${originAr}→${destAr} corridor`).toHaveCount(1);
  return row;
}

async function fillPrices(page: Page, min: number, suggested: number, max: number) {
  const dialog = page.getByRole("dialog");
  await dialog.getByLabel("أدنى سعر").fill(String(min));
  await dialog.getByLabel("السعر المقترح").fill(String(suggested));
  await dialog.getByLabel("أعلى سعر").fill(String(max));
}

test("the list is usable at full size — one page of rows, not all of them", async ({
  page,
  request,
}) => {
  const corridors = await fetchCorridors(request);
  await page.goto("/corridors");

  // The exact total the API holds, rendered in Arabic-Indic digits. Asserting
  // the real number (not "some digits appeared") is what makes this fail if the
  // list silently truncates or double-counts.
  await expect(page.getByText(`${toArabicDigits(corridors.length)} ممر`)).toBeVisible();

  // 300+ corridors must NOT all be in the DOM — that is the difference between
  // a list that works at real size and one that only works in a demo.
  await expect(page.locator("tbody tr")).toHaveCount(PAGE_SIZE);
  await expect(page.getByRole("button", { name: "الصفحة التالية" })).toBeEnabled();
});

test("search by city returns exactly the corridors touching that city", async ({ page }) => {
  await page.goto("/corridors");

  // Baghdad is deliberately not one of the reserved pairs, so its count is
  // 17 origins + 17 destinations = 34 no matter which other tests have run.
  await page.getByLabel("ابحث بالمدينة").fill("بغداد");

  await expect(page.getByText(new RegExp(`^${toArabicDigits(CORRIDORS_PER_CITY)} من `))).toBeVisible();

  // Every row on the page really does involve Baghdad — a filter that returned
  // the right COUNT of wrong rows would pass a count-only assertion.
  const rows = page.locator("tbody tr");
  await expect(rows).toHaveCount(PAGE_SIZE);
  for (const row of await rows.all()) {
    await expect(row).toContainText("بغداد");
  }

  // The remainder is on page 2: 34 - 25 = 9.
  await page.getByRole("button", { name: "الصفحة التالية" }).click();
  await expect(page.locator("tbody tr")).toHaveCount(CORRIDORS_PER_CITY - PAGE_SIZE);
});

test("a search that matches nothing says so instead of showing everything", async ({ page }) => {
  await page.goto("/corridors");
  await page.getByLabel("ابحث بالمدينة").fill("مدينة-لا-توجد");

  await expect(page.getByText("لا ممر يطابق البحث")).toBeVisible();
  await expect(page.locator("tbody tr")).toHaveCount(0);
});

test("an inverted price band is rejected per-field, before it reaches the server", async ({
  page,
}) => {
  await openCreateDialog(page);
  await selectCity(page, "من", FREE_CORRIDOR.originAr);
  await selectCity(page, "إلى", FREE_CORRIDOR.destAr);

  // min > max: the band itself is impossible.
  await fillPrices(page, 20000, 15000, 10000);
  await page.getByRole("button", { name: "إنشاء" }).click();

  // The error must name the offending FIELD. A form-level banner would leave
  // the admin guessing which of three numbers to change.
  await expect(page.getByText("أعلى سعر يجب ألّا يقل عن أدنى سعر.")).toBeVisible();
  // Still open, nothing saved.
  await expect(page.getByRole("dialog")).toBeVisible();
});

test("a suggestion outside the band is rejected on the suggestion field", async ({ page }) => {
  await openCreateDialog(page);
  await selectCity(page, "من", FREE_CORRIDOR.originAr);
  await selectCity(page, "إلى", FREE_CORRIDOR.destAr);

  // Band is coherent (10k–20k) but the suggestion sits above it.
  await fillPrices(page, 10000, 25000, 20000);
  await page.getByRole("button", { name: "إنشاء" }).click();

  await expect(page.getByText("السعر المقترح يجب ألّا يزيد على أعلى سعر.")).toBeVisible();
  await expect(page.getByRole("dialog")).toBeVisible();
});

test("a duplicate city pair is refused with the backend's Arabic message", async ({ page }) => {
  await openCreateDialog(page);
  await selectCity(page, "من", EXISTING_CORRIDOR.originAr);
  await selectCity(page, "إلى", EXISTING_CORRIDOR.destAr);
  await fillPrices(page, 8000, 12000, 20000);
  await page.getByRole("button", { name: "إنشاء" }).click();

  // This one can only come from the server — the form has no idea which pairs
  // are taken, so seeing it proves the round trip and the 409 mapping.
  await expect(page.getByRole("alert")).toContainText(DUPLICATE_CORRIDOR_MESSAGE);
  await expect(page.getByRole("dialog")).toBeVisible();
});

test("a valid corridor saves and appears in the list", async ({ page, request }) => {
  await openCreateDialog(page);
  await selectCity(page, "من", FREE_CORRIDOR.originAr);
  await selectCity(page, "إلى", FREE_CORRIDOR.destAr);
  await fillPrices(page, 30000, 50000, 80000);
  await page.getByRole("button", { name: "إنشاء" }).click();

  await expect(page.getByRole("dialog")).toBeHidden();

  // Found through the panel's own filters, the way an admin would confirm it.
  const row = await filterToPair(page, FREE_CORRIDOR.originAr, FREE_CORRIDOR.destAr);
  await expect(row).toContainText(formatIqd(50000));

  // …and it really is in the database, not just on the screen.
  const corridors = await fetchCorridors(request);
  const created = corridors.find(
    (c) => c.originCity === FREE_CORRIDOR.origin && c.destCity === FREE_CORRIDOR.dest,
  );
  expect(created, "the corridor was not persisted").toBeDefined();
  expect(created).toMatchObject({
    minPricePerSeat: 30000,
    suggestedPricePerSeat: 50000,
    maxPricePerSeat: 80000,
    active: true,
  });
});

test("editing a price persists it", async ({ page, request }) => {
  const newSuggested = EDITABLE_CORRIDOR.suggested + 2500;

  const row = await filterToPair(page, EDITABLE_CORRIDOR.originAr, EDITABLE_CORRIDOR.destAr);
  await row.getByRole("button", { name: "تعديل الممر" }).click();

  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  // The form opens on the CURRENT value — an edit dialog that opened blank
  // would silently wipe the other two prices on save.
  await expect(dialog.getByLabel("السعر المقترح")).toHaveValue(String(EDITABLE_CORRIDOR.suggested));

  await dialog.getByLabel("السعر المقترح").fill(String(newSuggested));
  await page.getByRole("button", { name: "حفظ" }).click();
  await expect(dialog).toBeHidden();

  await expect(row).toContainText(formatIqd(newSuggested));

  const corridors = await fetchCorridors(request);
  const edited = corridors.find(
    (c) => c.originCity === EDITABLE_CORRIDOR.origin && c.destCity === EDITABLE_CORRIDOR.dest,
  );
  expect(edited?.suggestedPricePerSeat).toBe(newSuggested);
});

test("toggling a corridor off persists across a reload", async ({ page, request }) => {
  const row = await filterToPair(page, TOGGLEABLE_CORRIDOR.originAr, TOGGLEABLE_CORRIDOR.destAr);
  await expect(row).toContainText("نشط");

  await row.getByRole("switch").click();
  await expect(row).toContainText("غير نشط");

  // A reload is the difference between "the switch moved" and "the corridor is
  // off" — optimistic UI would pass the first and fail the second.
  const reloaded = await filterToPair(
    page,
    TOGGLEABLE_CORRIDOR.originAr,
    TOGGLEABLE_CORRIDOR.destAr,
  );
  await expect(reloaded).toContainText("غير نشط");

  const corridors = await fetchCorridors(request);
  const toggled = corridors.find(
    (c) => c.originCity === TOGGLEABLE_CORRIDOR.origin && c.destCity === TOGGLEABLE_CORRIDOR.dest,
  );
  expect(toggled?.active).toBe(false);
});
