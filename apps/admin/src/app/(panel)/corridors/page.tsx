import { redirect } from "next/navigation";
import { AlertTriangle } from "lucide-react";

import { getAuthToken } from "@/lib/auth-cookie";
import { ApiError, listCorridors } from "@/lib/backend";
import type { Corridor } from "@/lib/types";
import { CorridorsClient } from "./corridors-client";

export default async function CorridorsPage() {
  const token = await getAuthToken();
  if (!token) {
    redirect("/login");
  }

  // Fetch only — JSX is constructed after the try/catch so a render error
  // from a child component is never (mis)caught as a fetch/auth error here.
  let corridors: Corridor[] | null = null;
  let errorMessage: string | null = null;
  try {
    corridors = await listCorridors(token);
  } catch (err) {
    if (err instanceof ApiError && err.statusCode === 401) {
      // Server Components can't mutate cookies during render — route through
      // the logout Route Handler, which clears the cookie then redirects.
      redirect("/api/auth/logout");
    }
    errorMessage =
      err instanceof ApiError ? err.message : "حدث خطأ غير متوقع. حاول مرة أخرى.";
  }

  if (corridors) {
    return <CorridorsClient corridors={corridors} />;
  }

  return (
    <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
      <div className="flex size-14 items-center justify-center rounded-full bg-destructive/10 text-destructive">
        <AlertTriangle className="size-6" />
      </div>
      <p className="font-medium">{errorMessage}</p>
      <p className="text-sm text-muted-foreground">أعد تحميل الصفحة للمحاولة مرة أخرى.</p>
    </div>
  );
}
