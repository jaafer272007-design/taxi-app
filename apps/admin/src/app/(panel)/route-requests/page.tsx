import { TriangleAlert } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import { ApiError, listRouteRequests } from "@/lib/backend";
import { RefreshBar } from "@/components/refresh-bar";
import { ROUTE_REQUESTS_REFRESH_MS } from "@/lib/refresh";
import type { RouteRequestsPayload } from "@/lib/types";
import { RouteRequestsClient } from "./route-requests-client";

export const metadata = { title: "طلبات المسارات — تكسي" };

/**
 * الطلب مقابل العرض — أين نستقطب سائقين.
 *
 * ## المشكلة التي تحلّها هذه الشاشة
 *
 * ٣٠٦ ممرات، والسائقون يعلنون على حفنة منها. قبل هذه الشاشة كان اختيار الممر
 * الذي نعمل عليه **تخميناً**: ما عندنا أي إشارة من الركّاب الذين بحثوا في مسار
 * فارغ وغادروا.
 *
 * الآن كل راكب يبحث في مسار بلا رحلات يقدر يقول «أريد هذا المسار» بنقرة، وهذه
 * الشاشة ترتّب الممرات بحسب ذلك الطلب.
 *
 * ## الفلتر هو الميزة
 *
 * «طلب بلا عرض» يعزل القائمة القابلة للتنفيذ: ممرّ عليه طلب وما عليه أي رحلة
 * حيّة. القائمة الكاملة سياق؛ هذه هي قائمة العمل.
 *
 * `?unserved=1` يبقى في العنوان حتى يبقى الفلتر بعد التحديث التلقائي — الشاشة
 * تُحدَّث كل دقيقة، وفلترٌ يضيع كل دقيقة أسوأ من لا فلتر.
 */
export default async function RouteRequestsPage({
  searchParams,
}: {
  searchParams: Promise<{ unserved?: string }>;
}) {
  const { token } = await requireAdmin();
  const { unserved } = await searchParams;
  const unservedOnly = unserved === "1";

  let payload: RouteRequestsPayload | null = null;
  let errorMessage: string | null = null;

  try {
    payload = await listRouteRequests(token, { unservedOnly });
  } catch (err) {
    errorMessage = err instanceof ApiError ? err.message : "حدث خطأ غير متوقع.";
  }

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">طلبات المسارات</h1>
          <p className="text-sm text-muted-foreground">
            مسارات طلبها ركّاب ولم يجدوا عليها رحلات — مرتّبة بحسب الطلب.
          </p>
        </div>
        <RefreshBar intervalMs={ROUTE_REQUESTS_REFRESH_MS} />
      </header>

      {errorMessage ? (
        <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
          <div className="flex size-14 items-center justify-center rounded-full bg-destructive-tonal text-destructive">
            <TriangleAlert className="size-6" />
          </div>
          <p className="font-medium">{errorMessage}</p>
          <p className="text-sm text-muted-foreground">أعد تحميل الصفحة للمحاولة مرة أخرى.</p>
        </div>
      ) : (
        <RouteRequestsClient payload={payload!} unservedOnly={unservedOnly} />
      )}
    </div>
  );
}
