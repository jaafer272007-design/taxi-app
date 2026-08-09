import { Search, TriangleAlert } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import {
  ApiError,
  getDriverView,
  getRiderView,
  getTripView,
  supportSearch,
} from "@/lib/backend";
import type {
  DriverSupportView,
  RiderSupportView,
  SupportSearchResult,
  TripSupportView,
} from "@/lib/types";
import { SearchBox } from "./search-box";
import { RiderDetail } from "./rider-detail";
import { DriverDetail } from "./driver-detail";
import { TripDetail } from "./trip-detail";

export const metadata = { title: "الدعم — تكسي" };

/**
 * أدوات الدعم.
 *
 * ## لماذا هذه الشاشة موجودة
 *
 * اللوحة كانت تعتمد سائقين وتسعّر ممرات، وأي شيء آخر كان يُنفَّذ بكتابة SQL
 * يدوياً — ثلاث مرات أثناء الاختبار وحده. أول يوم تشغيل حقيقي راح يتصل أحد
 * يقول «حجزي اختفى»، وبلا هذه الشاشة ما في وسيلة لمساعدته.
 *
 * ## عرض مميّز
 *
 * أرقام الهواتف تظهر هنا **بحكم الضرورة**: الدعم يبدأ برقم يتصل منه شخص، ولا
 * توجد وسيلة أخرى لربطه بحسابه. هذا لا يجعلها عامة — الشاشة كلها خلف جلسة
 * أدمن. أما **جهة اتصال الطوارئ** فلا تظهر هنا إطلاقاً، ولا في أي حمولة
 * ترجع من الخادم: بيانات الراكب الخاصة عن نفسه، وما في مهمة دعم تحتاجها.
 *
 * ## URL هو الحالة
 *
 * `?q=` و`?rider=` و`?driver=` و`?trip=` بالرابط، لا في `useState`: الدعم
 * يُنسَخ رابطه لزميل، ويُفتح من جديد بعد إعادة التحميل، ويرجع له زر الرجوع.
 */
export default async function SupportPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; rider?: string; driver?: string; trip?: string }>;
}) {
  const { token } = await requireAdmin();
  const { q, rider, driver, trip } = await searchParams;

  let result: SupportSearchResult | null = null;
  let riderView: RiderSupportView | null = null;
  let driverView: DriverSupportView | null = null;
  let tripView: TripSupportView | null = null;
  let errorMessage: string | null = null;

  try {
    if (q?.trim()) {
      result = await supportSearch(token, q);
      // A search that resolves to one thing opens it, rather than making the
      // admin read a result and click it — there is only ever one answer.
      if (result.kind === "TRIP" && !trip && !rider && !driver) {
        tripView = await getTripView(token, result.tripId);
      } else if (result.kind === "BOOKING" && !trip && !rider && !driver) {
        tripView = await getTripView(token, result.tripId);
      }
    }
    if (rider) riderView = await getRiderView(token, rider);
    if (driver) driverView = await getDriverView(token, driver);
    if (trip) tripView = await getTripView(token, trip);
  } catch (err) {
    errorMessage = err instanceof ApiError ? err.message : "حدث خطأ غير متوقع.";
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">الدعم</h1>
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
          ابحث برقم الهاتف، أو بمعرّف رحلة أو حجز. الأرقام هنا للاستعمال الداخلي
          فقط.
        </p>
      </div>

      <SearchBox initial={q ?? ""} />

      {errorMessage && (
        <div className="flex items-center gap-2 rounded-xl border border-destructive/40 bg-destructive-tonal p-4 text-sm text-destructive">
          <TriangleAlert className="size-4 shrink-0" />
          {errorMessage}
        </div>
      )}

      {result?.kind === "NOT_FOUND" && (
        <div className="rounded-xl border border-dashed border-border py-12 text-center text-sm text-muted-foreground">
          لا توجد نتيجة مطابقة
          {result.searchedPhone ? ` للرقم ${result.searchedPhone}` : ""}.
        </div>
      )}

      {result?.kind === "USER" && !riderView && !driverView && (
        <UserHit result={result} />
      )}

      {riderView && <RiderDetail view={riderView} />}
      {driverView && <DriverDetail view={driverView} />}
      {tripView && <TripDetail view={tripView} />}

      {!q && !rider && !driver && !trip && (
        <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
          <div className="flex size-14 items-center justify-center rounded-full bg-muted text-muted-foreground">
            <Search className="size-6" />
          </div>
          <p className="text-sm text-muted-foreground">
            ابدأ بالبحث عن راكب أو رحلة.
          </p>
        </div>
      )}
    </div>
  );
}

/**
 * A phone matched a user. One person can be both a rider and a driver on the
 * same account (the phone IS the identity), so both views are offered rather
 * than guessed at.
 */
function UserHit({
  result,
}: {
  result: Extract<SupportSearchResult, { kind: "USER" }>;
}) {
  return (
    <div className="rounded-xl border border-border p-4">
      <p className="font-medium">{result.user.name ?? "بدون اسم"}</p>
      {/* A number to dial and match — Western digits, forced LTR (CLAUDE.md). */}
      <p dir="ltr" className="text-start text-sm tabular-nums text-muted-foreground">
        {result.user.phone}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <a
          className="rounded-lg border border-border px-3 py-1.5 text-sm hover:bg-muted"
          href={`/support?rider=${result.user.id}`}
        >
          عرض كراكب
        </a>
        {result.driverProfileId && (
          <a
            className="rounded-lg border border-border px-3 py-1.5 text-sm hover:bg-muted"
            href={`/support?driver=${result.driverProfileId}`}
          >
            عرض كسائق
          </a>
        )}
      </div>
    </div>
  );
}
