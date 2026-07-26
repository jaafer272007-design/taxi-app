import { redirect } from "next/navigation";
import { Route, LogOut, CarTaxiFront } from "lucide-react";

import { getAuthToken } from "@/lib/auth-cookie";
import { ApiError, getMe } from "@/lib/backend";
import { Button } from "@/components/ui/button";
import { logoutAction } from "./actions";
import type { AuthUser } from "@/lib/types";

export default async function CorridorsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const token = await getAuthToken();
  if (!token) {
    redirect("/login");
  }

  // `redirect()` throws internally to signal Next.js's router, so it must
  // never be called from inside this try block — a surrounding catch would
  // swallow it as a generic error instead of letting the redirect happen.
  let me: AuthUser | null = null;
  try {
    me = await getMe(token);
  } catch (err) {
    if (err instanceof ApiError && err.statusCode === 401) {
      // Server Components can't mutate cookies during render — route through
      // the logout Route Handler, which clears the cookie then redirects.
      redirect("/api/auth/logout");
    }
    // Non-auth errors (e.g. network blip): keep the shell usable, just skip
    // showing the phone number rather than blocking the whole page.
  }

  // The backend's /auth/me and /corridors accept any authenticated user
  // (rider/driver JWTs included) — only /corridors writes are role-guarded
  // server-side. Re-check ADMIN here too, so a non-admin JWT set as this
  // app's cookie can't render the admin shell / read corridor pricing.
  if (me && !me.roles.includes("ADMIN")) {
    redirect("/api/auth/logout");
  }
  const adminPhone = me?.phone ?? "";

  return (
    <div className="flex min-h-dvh">
      <aside className="flex w-64 shrink-0 flex-col border-e border-sidebar-border bg-sidebar text-sidebar-foreground">
        <div className="flex items-center gap-2 px-5 py-5">
          <div className="flex size-9 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
            <CarTaxiFront className="size-5" />
          </div>
          <div>
            <p className="text-sm font-semibold">لوحة تحكم — تكسي</p>
            <p className="text-xs text-muted-foreground">النجف ↔ كربلاء وأكثر</p>
          </div>
        </div>

        <nav className="flex-1 space-y-1 px-3">
          <div className="flex items-center gap-2 rounded-md bg-sidebar-accent px-3 py-2 text-sm font-medium text-sidebar-accent-foreground">
            <Route className="size-4" />
            الممرات والتسعير
          </div>
        </nav>

        <div className="border-t border-sidebar-border p-3">
          {adminPhone && (
            <p className="px-3 pb-2 text-xs text-muted-foreground" dir="ltr">
              {adminPhone}
            </p>
          )}
          <form action={logoutAction}>
            <Button
              type="submit"
              variant="ghost"
              size="sm"
              className="w-full justify-start gap-2 text-muted-foreground"
            >
              <LogOut className="size-4" />
              تسجيل الخروج
            </Button>
          </form>
        </div>
      </aside>

      <main className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-5xl p-6 md:p-8">{children}</div>
      </main>
    </div>
  );
}
