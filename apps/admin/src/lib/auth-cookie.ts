import "server-only";
import { cookies } from "next/headers";

import { COOKIE_NAME } from "./auth-cookie-name";

/**
 * The admin JWT lives ONLY in an httpOnly cookie — never in client-side JS,
 * never in localStorage. Every corridor call is made server-side (Route
 * Handler / Server Action) using this cookie; the browser only ever holds an
 * opaque session cookie it cannot read or exfiltrate via XSS.
 */

// Matches the backend's default JWT_EXPIRES_IN ("30d", see services/api/.env.example).
const MAX_AGE_SECONDS = 60 * 60 * 24 * 30;

export async function getAuthToken(): Promise<string | null> {
  const store = await cookies();
  return store.get(COOKIE_NAME)?.value ?? null;
}

export async function setAuthCookie(token: string): Promise<void> {
  const store = await cookies();
  store.set(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: MAX_AGE_SECONDS,
  });
}

export async function clearAuthCookie(): Promise<void> {
  const store = await cookies();
  store.delete(COOKIE_NAME);
}

export { COOKIE_NAME };
