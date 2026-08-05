import { CarTaxiFront } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import { getDashboard } from "@/lib/backend";
import { PanelNav } from "./panel-nav";
import { LogoutButton } from "./logout-button";

/**
 * How many drivers are waiting to be reviewed, for the sidebar badge.
 *
 * Read from the dashboard aggregate rather than by listing PENDING drivers:
 * the backend already counts them, and a count is the whole answer. Failure is
 * swallowed — a badge is a hint, and taking the entire panel down because one
 * summary request timed out would be a spectacularly bad trade.
 */
async function pendingDriverCount(token: string): Promise<number> {
  try {
    const counts = await getDashboard(token);
    const pending = counts.drivers?.byStatus?.PENDING;
    return typeof pending === "number" && Number.isFinite(pending) ? pending : 0;
  } catch {
    return 0;
  }
}

/**
 * The authenticated shell. Everything under `(panel)` shares it; the route
 * group keeps the folder out of the URL, so this lives at `/dashboard`,
 * `/corridors`, … rather than `/panel/…`.
 *
 * `requireAdmin()` runs here on every render, which means a stale or non-admin
 * cookie is dropped before any page content is produced. It is not the security
 * boundary — the backend is — but it stops the panel from rendering a shell
 * whose every button would 403.
 */
export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const { me, token } = await requireAdmin();
  const isSuperAdmin = me.role === "SUPER_ADMIN";
  const pendingDrivers = await pendingDriverCount(token);

  return (
    <div className="flex min-h-dvh">
      <aside className="flex w-64 shrink-0 flex-col border-e border-sidebar-border bg-sidebar text-sidebar-foreground">
        <div className="flex items-center gap-3 px-5 py-5">
          <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-sidebar-primary text-sidebar-primary-foreground">
            <CarTaxiFront className="size-5" />
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-bold">لوحة تحكم — تكسي</p>
            <p className="truncate text-xs text-muted-foreground">مَسار · نقل مشترك</p>
          </div>
        </div>

        {/* The nav item for admin management is only rendered for the super
            admin — but /admins re-checks the role server-side, so hiding it is
            tidiness, not protection. */}
        <PanelNav isSuperAdmin={isSuperAdmin} pendingDrivers={pendingDrivers} />

        <div className="border-t border-sidebar-border p-3">
          <div className="px-3 pb-2">
            <p className="truncate text-sm font-semibold" dir="ltr">
              {me.username}
            </p>
            <p className="text-xs text-muted-foreground">
              {isSuperAdmin ? "مدير أعلى" : "مدير"}
            </p>
          </div>
          <LogoutButton />
        </div>
      </aside>

      <main className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-5xl p-6 md:p-8">{children}</div>
      </main>
    </div>
  );
}
