import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import { COOKIE_NAME } from "@/lib/auth-cookie-name";

/**
 * Optimistic auth gate (Next.js 16 renamed `middleware.ts` → `proxy.ts`; same
 * mechanism). This ONLY checks whether the session cookie is present — it
 * never decodes or verifies the JWT here. The real authorization boundary is
 * the backend's RolesGuard on every /corridors write; this just keeps a
 * logged-out browser from rendering the shell before redirecting to /login.
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
    url.pathname = "/corridors";
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
