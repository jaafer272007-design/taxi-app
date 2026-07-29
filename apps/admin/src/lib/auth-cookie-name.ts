/**
 * Just the cookie name — no `server-only` / `next/headers` imports, so this
 * is safe to import from `proxy.ts` (Edge runtime) AND from server-only code
 * (`auth-cookie.ts`) without coupling those two different bundle targets.
 */
export const COOKIE_NAME = "admin_token";
