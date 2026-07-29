import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import { COOKIE_NAME } from "@/lib/auth-cookie-name";

/**
 * Optimistic auth gate (Next.js 16 renamed `middleware.ts` → `proxy.ts`; same
 * mechanism). This ONLY checks whether the session cookie is PRESENT — it never
 * decodes or verifies the JWT, and it knows nothing about roles.
 *
 * The real authorization boundary is the backend: RolesGuard on the
 * operational endpoints, SuperAdminGuard on /admin/users. In between,
 * `requireAdmin()` / `requireSuperAdmin()` re-read the session server-side on
 * every page and every Server Action. This layer exists only so a logged-out
 * browser doesn't render the shell for a frame before being redirected.
 */
export function proxy(request: NextRequest) {
  const hasSession = request.cookies.has(COOKIE_NAME);
  const isLoginPage = request.nextUrl.pathname.startsWith("/login");

  if (!hasSession && !isLoginPage) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  if (hasSession && isLoginPage) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
