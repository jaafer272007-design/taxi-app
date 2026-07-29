import "server-only";

import { redirect } from "next/navigation";

import { getAuthToken } from "./auth-cookie";
import { ApiError, getAdminMe } from "./backend";
import type { AdminMe } from "./types";

/**
 * Resolves the signed-in admin, server-side, from the httpOnly cookie.
 *
 * Every panel page and every Server Action goes through here. That matters
 * because a Server Action is a POST endpoint reachable by anyone who can send
 * the request — rendering a page only for super admins is a UI decision, not a
 * security boundary, so the check has to happen inside the action too.
 *
 * The real authorization boundary is still the backend: `/admin/users` returns
 * 403 to a normal ADMIN whatever this app believes. This function exists so the
 * panel fails early and legibly rather than rendering a page that will 403 on
 * every button.
 */
export async function requireAdmin(): Promise<{ token: string; me: AdminMe }> {
  const token = await getAuthToken();
  if (!token) {
    redirect("/login");
  }

  try {
    const me = await getAdminMe(token);
    return { token, me };
  } catch (err) {
    // A rider/driver JWT authenticates against the backend but is not an admin
    // session: /admin/auth/me 401s it, and we drop the cookie rather than
    // rendering the shell for it.
    if (err instanceof ApiError && (err.statusCode === 401 || err.statusCode === 403)) {
      // Server Components cannot mutate cookies during render, so clearing the
      // cookie has to go through the logout Route Handler.
      redirect("/api/auth/logout");
    }
    throw err;
  }
}

/**
 * Like {@link requireAdmin}, but additionally refuses anyone who is not the
 * super admin — used by the admin-management page and its actions.
 */
export async function requireSuperAdmin(): Promise<{ token: string; me: AdminMe }> {
  const session = await requireAdmin();
  if (session.me.role !== "SUPER_ADMIN") {
    redirect("/dashboard");
  }
  return session;
}
