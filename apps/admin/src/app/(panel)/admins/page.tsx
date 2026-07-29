import { TriangleAlert } from "lucide-react";

import { requireSuperAdmin } from "@/lib/admin-session";
import { ApiError, listAdmins } from "@/lib/backend";
import type { AdminAccount } from "@/lib/types";
import { AdminsClient } from "./admins-client";

export const metadata = { title: "إدارة المدراء — تكسي" };

/**
 * SUPER_ADMIN only. `requireSuperAdmin()` redirects a normal ADMIN who reaches
 * this URL directly — and even if that check were bypassed, `/admin/users`
 * returns 403 to them, so the page would render empty rather than leak.
 */
export default async function AdminsPage() {
  const { token, me } = await requireSuperAdmin();

  let admins: AdminAccount[] | null = null;
  let errorMessage: string | null = null;
  try {
    admins = await listAdmins(token);
  } catch (err) {
    errorMessage = err instanceof ApiError ? err.message : "حدث خطأ غير متوقع.";
  }

  if (admins) {
    return <AdminsClient admins={admins} currentAdminId={me.id} />;
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
