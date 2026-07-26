import { NextResponse } from "next/server";

import { clearAuthCookie } from "@/lib/auth-cookie";

export async function POST() {
  await clearAuthCookie();
  return NextResponse.json({ ok: true });
}

/**
 * Server Components can't mutate cookies during render (Next.js throws
 * `ReadonlyRequestCookiesError`). When a Server Component detects a stale/
 * invalid session (401 from the backend), it must `redirect()` here instead
 * of calling `clearAuthCookie()` directly — Route Handlers run outside the
 * render phase, so the cookie mutation is allowed.
 */
export async function GET(request: Request) {
  await clearAuthCookie();
  return NextResponse.redirect(new URL("/login", request.url));
}
