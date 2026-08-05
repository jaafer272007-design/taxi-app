import { Banknote, IdCard, Route as RouteIcon, Ticket, TriangleAlert, Users } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import { ApiError, getDashboard } from "@/lib/backend";
import { formatCount, formatPrice } from "@/lib/format";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { RefreshBar } from "@/components/refresh-bar";
import { DASHBOARD_REFRESH_MS } from "@/lib/refresh";
import type { DashboardCounts } from "@/lib/types";

export const metadata = { title: "لوحة المعلومات — تكسي" };

/** Arabic labels for the per-status breakdowns the backend groups by. */
const DRIVER_STATUS: Record<string, string> = {
  PENDING: "بانتظار المراجعة",
  APPROVED: "معتمدون",
  REJECTED: "مرفوضون",
  SUSPENDED: "موقوفون",
};

const TRIP_STATUS: Record<string, string> = {
  OPEN: "مفتوحة",
  LOCKED: "مكتملة الحجز",
  EN_ROUTE: "جارية",
  COMPLETED: "منتهية",
  SETTLED: "مسوّاة",
  CANCELLED: "ملغاة",
};

/**
 * A count that may be absent.
 *
 * `formatCount(undefined as never)` would render "NaN"; on a screen that also
 * shows collected cash, a number that is merely *missing* must never be
 * mistaken for a number that is wrong. Absent reads as `—`.
 */
function count(value: number | undefined): string {
  return typeof value === "number" && Number.isFinite(value) ? formatCount(value) : "—";
}

function money(value: number | undefined): string {
  return typeof value === "number" && Number.isFinite(value) ? formatPrice(value) : "—";
}

export default async function DashboardPage() {
  const { token } = await requireAdmin();

  let counts: DashboardCounts | null = null;
  let error: string | null = null;
  try {
    counts = await getDashboard(token);
  } catch (err) {
    // A dashboard is a read-only summary — if it fails, say so plainly rather
    // than taking the panel down. The other sections still work.
    error = err instanceof ApiError ? err.message : "تعذّر تحميل الإحصاءات.";
  }

  return (
    <div className="space-y-8">
      {/* A slower beat than /drivers on purpose: these are figures watched
          over a shift, not a queue anyone is blocked behind. */}
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">لوحة المعلومات</h1>
          <p className="text-sm text-muted-foreground">نظرة سريعة على حالة المنصة.</p>
        </div>
        <RefreshBar intervalMs={DASHBOARD_REFRESH_MS} />
      </header>

      {error && (
        <p
          role="alert"
          className="flex items-start gap-2 rounded-xl bg-warning-tonal p-4 text-sm text-warning"
        >
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          <span>{error}</span>
        </p>
      )}

      {counts && (
        <>
          <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Stat icon={Users} label="الركّاب" value={count(counts.riders)} />
            <Stat icon={IdCard} label="السائقون" value={count(counts.drivers?.total)} />
            <Stat
              icon={RouteIcon}
              label="الرحلات"
              value={count(counts.trips?.total)}
              hint={`اليوم: ${count(counts.trips?.today)}`}
            />
            <Stat icon={Ticket} label="الحجوزات" value={count(counts.bookings)} />
          </section>

          <section>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
                  <Banknote className="size-4" />
                  إجمالي النقد المحصّل
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-3xl font-bold tabular-nums text-primary">
                  {money(counts.earningsTotal)}
                </p>
                <p className="mt-1 text-xs text-muted-foreground">
                  مجموع ما حصّله السائقون نقداً منذ البداية.
                </p>
              </CardContent>
            </Card>
          </section>

          <Breakdown
            title="السائقون حسب الحالة"
            icon={IdCard}
            labels={DRIVER_STATUS}
            values={counts.drivers?.byStatus}
          />
          <Breakdown
            title="الرحلات حسب الحالة"
            icon={RouteIcon}
            labels={TRIP_STATUS}
            values={counts.trips?.byStatus}
          />
        </>
      )}
    </div>
  );
}

function Stat({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
          <Icon className="size-4" />
          {label}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-3xl font-bold tabular-nums">{value}</p>
        {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  );
}

function Breakdown({
  title,
  icon: Icon,
  labels,
  values,
}: {
  title: string;
  icon: LucideIcon;
  labels: Record<string, string>;
  values?: Record<string, number>;
}) {
  const entries = Object.entries(values ?? {});

  return (
    <section className="space-y-3">
      <h2 className="flex items-center gap-2 text-sm font-semibold text-muted-foreground">
        <Icon className="size-4" />
        {title}
      </h2>
      {entries.length === 0 ? (
        <p className="rounded-xl border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
          لا توجد بيانات بعد.
        </p>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {entries.map(([key, value]) => (
            <Card key={key}>
              <CardHeader className="pb-2">
                {/* An unknown key falls back to the raw key rather than
                    rendering blank — a status the backend adds should be
                    visible, not silently dropped. */}
                <CardTitle className="text-sm font-medium text-muted-foreground">
                  {labels[key] ?? key}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-3xl font-bold tabular-nums">{count(value)}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </section>
  );
}
