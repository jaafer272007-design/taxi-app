import { TriangleAlert } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import { ApiError, listDrivers } from "@/lib/backend";
import type { Driver, DriverStatus } from "@/lib/types";
import { DriversClient } from "./drivers-client";

export const metadata = { title: "السائقون — تكسي" };

const STATUSES: readonly DriverStatus[] = ["PENDING", "APPROVED", "SUSPENDED", "REJECTED"];

function parseStatus(raw: string | undefined): DriverStatus | undefined {
  return STATUSES.includes(raw as DriverStatus) ? (raw as DriverStatus) : undefined;
}

export default async function DriversPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { token } = await requireAdmin();
  const { status: rawStatus } = await searchParams;
  // Anything unrecognised falls back to "all" rather than being forwarded to
  // the backend as a bad enum.
  const status = parseStatus(rawStatus);

  // Fetch only — the JSX is built after the try/catch so a render error in a
  // child is never mistaken for a fetch failure here.
  let drivers: Driver[] | null = null;
  let errorMessage: string | null = null;
  try {
    drivers = await listDrivers(token, status);
  } catch (err) {
    errorMessage = err instanceof ApiError ? err.message : "حدث خطأ غير متوقع.";
  }

  if (drivers) {
    return <DriversClient drivers={drivers} status={status} />;
  }

  return (
    <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
      <div className="flex size-14 items-center justify-center rounded-full bg-destructive-tonal text-destructive">
        <TriangleAlert className="size-6" />
      </div>
      <p className="font-medium">{errorMessage}</p>
      <p className="text-sm text-muted-foreground">أعد تحميل الصفحة للمحاولة مرة أخرى.</p>
    </div>
  );
}
