import { test, expect } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  NORMAL_ADMIN,
  NORMAL_ADMIN_STATE,
  SUPPORT_CASE,
  apiLogin,
  authHeader,
  toArabicDigits,
} from "./fixtures";

/**
 * أدوات الدعم، من طرف إلى طرف.
 *
 * ## لماذا هذا الملف موجود
 *
 * الادّعاء الذي يستحق الاختبار هنا ليس «الـendpoint يرجع 200». هو:
 * **أدمن يبحث برقم هاتف، يفتح حجزاً، يلغيه بسبب مكتوب — فيرجع المقعد فعلاً
 * ويظهر الإجراء بالسجل**. تلك سلسلة تمرّ باللوحة والخادم وآلة الحالة معاً،
 * ولا يقدر أي اختبار وحدة أن يدّعيها.
 *
 * التأكيد الأخير يقرأ **الخادم** لا الصفحة: الصفحة قد تعرض نسخة قديمة، وعدد
 * المقاعد هو الرقم الذي يقرّر إن كان بإمكان راكب آخر أن يحجز.
 *
 * ## يعدّل الحالة
 *
 * الإلغاء يستهلك حالة الزرع، فالاختبارات متسلسلة ويُعاد بناء الحالة بكل تشغيل.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

test.describe.configure({ mode: "serial" });

/**
 * The seeded case, read from the API rather than guessed at.
 *
 * [requireConfirmed] is false for the read-only checks: they run AFTER the
 * cancel in serial order, so by then the booking is CANCELLED — and demanding
 * a confirmed one there would fail for a reason that has nothing to do with
 * what is being asserted.
 */
async function seededCase(
  request: Parameters<typeof apiLogin>[0],
  token: string,
  { requireConfirmed = true }: { requireConfirmed?: boolean } = {},
) {
  const res = await request.get(
    `${API_URL}/admin/support/search?q=${encodeURIComponent(SUPPORT_CASE.riderPhone)}`,
    { headers: authHeader(token) },
  );
  const hit = (await res.json()) as { kind: string; user: { id: string } };
  expect(hit.kind, "the seeded support rider should be findable by phone").toBe("USER");

  const riderRes = await request.get(`${API_URL}/admin/support/riders/${hit.user.id}`, {
    headers: authHeader(token),
  });
  const rider = (await riderRes.json()) as {
    bookings: { id: string; tripId: string; status: string }[];
  };
  const booking = requireConfirmed
    ? rider.bookings.find((b) => b.status === "CONFIRMED")
    : rider.bookings[0];
  expect(booking, "the seed should leave a booking on the support trip").toBeDefined();
  return { riderId: hit.user.id, ...booking! };
}

test.describe("support lookup", () => {
  test("finds a rider by phone and opens their booking history", async ({ page }) => {
    await page.goto("/support");
    await page.getByLabel("بحث").fill(SUPPORT_CASE.riderPhone);
    await page.getByRole("button", { name: "بحث" }).click();

    await expect(page.getByText(SUPPORT_CASE.riderName)).toBeVisible();
    await page.getByRole("link", { name: "عرض كراكب" }).click();

    await expect(page.getByRole("heading", { name: SUPPORT_CASE.riderName })).toBeVisible();
    await expect(page.getByRole("heading", { name: /الحجوزات/ })).toBeVisible();
    // The booking the seed created, with its trip context.
    await expect(page.getByText("النجف إلى كربلاء").first()).toBeVisible();
    await expect(page.getByText("مؤكد").first()).toBeVisible();
  });

  test("a trip id opens the trip with its bookings and the rider behind each", async ({
    page,
    request,
  }) => {
    const token = await apiLogin(request, NORMAL_ADMIN);
    const { tripId } = await seededCase(request, token);

    await page.goto("/support");
    await page.getByLabel("بحث").fill(tripId);
    await page.getByRole("button", { name: "بحث" }).click();

    await expect(page.getByRole("heading", { name: "النجف إلى كربلاء" })).toBeVisible();
    await expect(page.getByText(SUPPORT_CASE.driverName)).toBeVisible();
    // The plate stays Western — an identifier matched against a metal plate.
    await expect(page.getByText(SUPPORT_CASE.plate)).toBeVisible();
    await expect(page.getByText(SUPPORT_CASE.riderName)).toBeVisible();
    await expect(page.getByText("حي السلام")).toBeVisible();
    // Seats free before anyone intervenes.
    await expect(
      page.getByText(`${toArabicDigits(1)} من ${toArabicDigits(SUPPORT_CASE.seatsTotal)}`),
    ).toBeVisible();
  });

  test("an unknown query says so rather than guessing", async ({ page }) => {
    await page.goto("/support?q=definitely-not-an-id");
    await expect(page.getByText(/لا توجد نتيجة مطابقة/)).toBeVisible();
  });
});

test.describe("intervention", () => {
  test("a reason is required before anything can be cancelled", async ({ page, request }) => {
    const token = await apiLogin(request, NORMAL_ADMIN);
    const { tripId } = await seededCase(request, token);

    await page.goto(`/support?trip=${tripId}`);
    await page.getByRole("button", { name: "ألغِ الحجز" }).first().click();

    const confirm = page.getByRole("button", { name: "ألغِ الحجز" }).last();
    await expect(confirm).toBeDisabled();
    await page.getByLabel("السبب (مطلوب)").fill("لا");
    await expect(confirm).toBeDisabled();
  });

  test("cancelling a booking RETURNS THE SEAT and lands in the audit log", async ({
    page,
    request,
  }) => {
    const token = await apiLogin(request, NORMAL_ADMIN);
    const { tripId, id: bookingId } = await seededCase(request, token);
    const reason = "اتصل الراكب — حجز بالخطأ";

    await page.goto(`/support?trip=${tripId}`);
    await page.getByRole("button", { name: "ألغِ الحجز" }).first().click();
    await page.getByLabel("السبب (مطلوب)").fill(reason);
    await page.getByRole("button", { name: "ألغِ الحجز" }).last().click();

    await expect(page.getByText("ملغى").first()).toBeVisible();

    // Asked of the SERVER, not the page: the seat count is what decides
    // whether another rider can book, and a re-rendered page could be stale.
    const res = await request.get(`${API_URL}/admin/support/trips/${tripId}`, {
      headers: authHeader(token),
    });
    const view = (await res.json()) as { trip: { seatsAvailable: number } };
    expect(
      view.trip.seatsAvailable,
      "the seat must come back — a raw status write would leave this unchanged",
    ).toBe(SUPPORT_CASE.seatsFreeAfter);

    // And the intervention is on the record, with the admin who did it.
    const log = await request.get(`${API_URL}/admin/support/actions?entityId=${bookingId}`, {
      headers: authHeader(token),
    });
    const rows = (await log.json()) as {
      type: string;
      adminUsername: string;
      reason: string;
    }[];
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      type: "BOOKING_CANCELLED",
      adminUsername: NORMAL_ADMIN.username,
      reason,
    });
  });

  test("the audit log page shows it, filterable by admin", async ({ page }) => {
    await page.goto("/actions");

    await expect(page.getByRole("heading", { name: "سجل الإجراءات" })).toBeVisible();
    await expect(page.getByText("إلغاء حجز").first()).toBeVisible();
    await expect(page.getByText(NORMAL_ADMIN.username).first()).toBeVisible();
    await expect(page.getByText("اتصل الراكب — حجز بالخطأ")).toBeVisible();

    // Filtering to an entity type that had no action empties the table, which
    // is how you can tell the filter is doing anything at all.
    await page.getByLabel("تصفية حسب نوع الكيان").selectOption("DRIVER");
    await expect(page.getByText("لا توجد إجراءات مطابقة")).toBeVisible();
  });
});

test.describe("privacy", () => {
  test("no support page carries an emergency contact", async ({ page, request }) => {
    // The seeded rider has none, so this asserts the SHAPE: the field name
    // never appears in a payload the panel renders. The value-level guard is
    // `emergency-contact.int-spec.ts`, which seeds one and searches for it.
    const token = await apiLogin(request, NORMAL_ADMIN);
    const { riderId, tripId } = await seededCase(request, token, {
      requireConfirmed: false,
    });

    for (const path of [`/admin/support/riders/${riderId}`, `/admin/support/trips/${tripId}`]) {
      const res = await request.get(`${API_URL}${path}`, { headers: authHeader(token) });
      const body = await res.text();
      expect(body, `${path} must not carry an emergency contact`).not.toContain(
        "emergencyContact",
      );
    }

    await page.goto(`/support?rider=${riderId}`);
    await expect(page.locator("body")).not.toContainText("جهة اتصال للطوارئ");
  });
});
