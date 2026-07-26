import "server-only";

import { ApiError, serverMessage } from "./api-error";
import type { AuthSession, AuthUser, Corridor } from "./types";

/**
 * Base URL of the taxi-app NestJS backend. Server-only — never sent to the
 * client. Same env-var name and default as the rider/driver Flutter apps
 * (see apps/rider/lib/config/app_config.dart) for one consistent convention.
 */
const API_BASE_URL = process.env.API_BASE_URL ?? "http://localhost:3000";

async function request<T>(
  path: string,
  init: RequestInit & { token?: string } = {},
): Promise<T> {
  const { token, headers, ...rest } = init;
  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      ...rest,
      cache: "no-store",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
    });
  } catch {
    throw new ApiError("تعذّر الاتصال بالخادم. تحقّق من الاتصال وحاول مرة أخرى.", {
      isNetwork: true,
    });
  }

  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // non-JSON error body — serverMessage() falls back to a status-based message
    }
    throw new ApiError(serverMessage(body, res.status), { statusCode: res.status });
  }

  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

// ── Auth ─────────────────────────────────────────────────────────────────

export function requestOtp(phone: string): Promise<void> {
  return request<void>("/auth/request-otp", {
    method: "POST",
    body: JSON.stringify({ phone }),
  });
}

export function verifyOtp(phone: string, code: string): Promise<AuthSession> {
  return request<AuthSession>("/auth/verify-otp", {
    method: "POST",
    body: JSON.stringify({ phone, code }),
  });
}

/** Re-fetches the current user server-side (never trusts a client-decoded JWT). */
export function getMe(token: string): Promise<AuthUser> {
  return request<AuthUser>("/auth/me", { token });
}

// ── Corridors ────────────────────────────────────────────────────────────

export function listCorridors(token: string): Promise<Corridor[]> {
  return request<Corridor[]>("/corridors", { token });
}

export function createCorridor(
  token: string,
  input: { originCity: string; destCity: string; pricePerSeat: number },
): Promise<Corridor> {
  return request<Corridor>("/corridors", {
    method: "POST",
    token,
    body: JSON.stringify(input),
  });
}

export function updateCorridor(
  token: string,
  id: string,
  input: Partial<{
    originCity: string;
    destCity: string;
    pricePerSeat: number;
    active: boolean;
  }>,
): Promise<Corridor> {
  return request<Corridor>(`/corridors/${id}`, {
    method: "PATCH",
    token,
    body: JSON.stringify(input),
  });
}

export { ApiError };
