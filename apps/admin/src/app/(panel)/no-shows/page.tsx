import { TriangleAlert } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import { ApiError, getRiderNoShows, listBlockedRiders } from "@/lib/backend";
import type { BlockedRidersPayload, RiderNoShowHistory } from "@/lib/types";
import { NoShowsClient } from "./no-shows-client";

export const metadata = { title: "عدم الحضور — تكسي" };

/**
 * The appeal desk.
 *
 * The automatic block is deliberately blunt — three no-shows in a month and the
 * rider cannot book for a week. Blunt is fine ONLY because this page exists: a
 * genuine emergency (a hospital, a funeral, a breakdown) must not be
 * indistinguishable from someone who simply does not turn up.
 *
 * So the admin can see every recorded no-show for a rider, void a single one,
 * or lift the whole block — always with a reason that is stored on the record.
 *
 * `?rider=` opens one rider's history beside the list, so the flow is
 * list → look → decide without losing the list.
 */
export default async function NoShowsPage({
  searchParams,
}: {
  searchParams: Promise<{ rider?: string }>;
}) {
  const { token } = await requireAdmin();
  const { rider: riderId } = await searchParams;

  let payload: BlockedRidersPayload | null = null;
  let history: RiderNoShowHistory | null = null;
  let errorMessage: string | null = null;

  try {
    payload = await listBlockedRiders(token);
    if (riderId) history = await getRiderNoShows(token, riderId);
  } catch (err) {
    errorMessage = err instanceof ApiError ? err.message : "حدث خطأ غير متوقع.";
  }

  if (payload) {
    return (
      <NoShowsClient payload={payload} history={history} selectedRiderId={riderId ?? null} />
    );
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
