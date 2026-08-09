import "server-only";

import { ApiError, serverMessage } from "./api-error";
import type {
  AdminAccount,
  AdminMe,
  AdminSession,
  BlockedRidersPayload,
  Corridor,
  DashboardCounts,
  Driver,
  DriverStatus,
  RiderNoShowHistory,
  AdminAction,
  DriverSupportView,
  RiderSupportView,
  SupportSearchResult,
  TripSupportView,
} from "./types";

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

// ── Admin auth ───────────────────────────────────────────────────────────
//
// Admins log in with a username and a password, NOT the rider/driver WhatsApp
// OTP flow. Both live behind the same JWT format; the backend tells them apart
// by a `kind` claim it sets itself.

export function adminLogin(username: string, password: string): Promise<AdminSession> {
  return request<AdminSession>("/admin/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

/**
 * Re-reads the signed-in admin server-side on every render. Never decode the
 * JWT in the browser to find the role — the nav item for admin management is
 * cosmetic, but the same answer decides whether we render a page at all, and
 * that has to come from the backend.
 */
export function getAdminMe(token: string): Promise<AdminMe> {
  return request<AdminMe>("/admin/auth/me", { token });
}

// ── Corridors ────────────────────────────────────────────────────────────

export function listCorridors(token: string): Promise<Corridor[]> {
  return request<Corridor[]>("/corridors", { token });
}

export function createCorridor(
  token: string,
  input: {
    originCity: string;
    destCity: string;
    suggestedPricePerSeat: number;
    minPricePerSeat: number;
    maxPricePerSeat: number;
  },
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
    suggestedPricePerSeat: number;
    minPricePerSeat: number;
    maxPricePerSeat: number;
    active: boolean;
  }>,
): Promise<Corridor> {
  return request<Corridor>(`/corridors/${id}`, {
    method: "PATCH",
    token,
    body: JSON.stringify(input),
  });
}

// ── Drivers ──────────────────────────────────────────────────────────────

export function listDrivers(token: string, status?: DriverStatus): Promise<Driver[]> {
  const query = status ? `?status=${encodeURIComponent(status)}` : "";
  return request<Driver[]>(`/admin/drivers${query}`, { token });
}

export function approveDriver(token: string, id: string): Promise<unknown> {
  return request(`/admin/drivers/${id}/approve`, { method: "POST", token });
}

export function rejectDriver(token: string, id: string, reason: string): Promise<unknown> {
  return request(`/admin/drivers/${id}/reject`, {
    method: "POST",
    token,
    body: JSON.stringify({ reason }),
  });
}

export function suspendDriver(token: string, id: string): Promise<unknown> {
  return request(`/admin/drivers/${id}/suspend`, { method: "POST", token });
}

// ── Dashboard ────────────────────────────────────────────────────────────

export function getDashboard(token: string): Promise<DashboardCounts> {
  return request<DashboardCounts>("/admin/dashboard", { token });
}

// ── Admin accounts (SUPER_ADMIN only — the backend returns 403 otherwise) ─

export function listAdmins(token: string): Promise<AdminAccount[]> {
  return request<AdminAccount[]>("/admin/users", { token });
}

export function createAdmin(
  token: string,
  input: { username: string; password: string },
): Promise<AdminAccount> {
  return request<AdminAccount>("/admin/users", {
    method: "POST",
    token,
    body: JSON.stringify(input),
  });
}

export function setAdminActive(
  token: string,
  id: string,
  active: boolean,
): Promise<AdminAccount> {
  return request<AdminAccount>(`/admin/users/${id}`, {
    method: "PATCH",
    token,
    body: JSON.stringify({ active }),
  });
}

export function resetAdminPassword(
  token: string,
  id: string,
  password: string,
): Promise<AdminAccount> {
  return request<AdminAccount>(`/admin/users/${id}/password`, {
    method: "POST",
    token,
    body: JSON.stringify({ password }),
  });
}

export { ApiError };

// ── No-shows (rider reputation + temporary block) ────────────────────────

export function listBlockedRiders(token: string): Promise<BlockedRidersPayload> {
  return request<BlockedRidersPayload>("/admin/no-shows/blocked", { token });
}

export function getRiderNoShows(token: string, riderId: string): Promise<RiderNoShowHistory> {
  return request<RiderNoShowHistory>(`/admin/no-shows/rider/${riderId}`, { token });
}

export function voidNoShow(token: string, id: string, reason: string): Promise<unknown> {
  return request(`/admin/no-shows/${id}/void`, {
    method: "POST",
    token,
    body: JSON.stringify({ reason }),
  });
}

export function liftRiderBlock(token: string, riderId: string, reason: string): Promise<unknown> {
  return request(`/admin/no-shows/rider/${riderId}/lift`, {
    method: "POST",
    token,
    body: JSON.stringify({ reason }),
  });
}

// ── Support tools ────────────────────────────────────────────────────────
//
// Phone numbers come back from these and are shown to admins by necessity —
// support begins with a number someone is calling from. That is a PRIVILEGED
// view, not a public one. Emergency contacts are never included: the backend
// does not select them, and its integration spec asserts so.

export function supportSearch(token: string, q: string): Promise<SupportSearchResult> {
  return request<SupportSearchResult>(
    `/admin/support/search?q=${encodeURIComponent(q)}`,
    { token },
  );
}

export function getRiderView(token: string, userId: string): Promise<RiderSupportView> {
  return request<RiderSupportView>(`/admin/support/riders/${userId}`, { token });
}

export function getDriverView(token: string, profileId: string): Promise<DriverSupportView> {
  return request<DriverSupportView>(`/admin/support/drivers/${profileId}`, { token });
}

export function getTripView(token: string, tripId: string): Promise<TripSupportView> {
  return request<TripSupportView>(`/admin/support/trips/${tripId}`, { token });
}

export function listAdminActions(
  token: string,
  filter: { adminId?: string; entityType?: string; entityId?: string } = {},
): Promise<AdminAction[]> {
  const params = new URLSearchParams();
  if (filter.adminId) params.set("adminId", filter.adminId);
  if (filter.entityType) params.set("entityType", filter.entityType);
  if (filter.entityId) params.set("entityId", filter.entityId);
  const query = params.toString();
  return request<AdminAction[]>(`/admin/support/actions${query ? `?${query}` : ""}`, {
    token,
  });
}

export function listActionAdmins(
  token: string,
): Promise<{ adminId: string; adminUsername: string }[]> {
  return request<{ adminId: string; adminUsername: string }[]>(
    "/admin/support/actions/admins",
    { token },
  );
}

/** Every intervention takes a reason; the acting admin comes from the JWT. */
function intervene(token: string, path: string, reason: string): Promise<unknown> {
  return request(path, { method: "POST", token, body: JSON.stringify({ reason }) });
}

export const cancelBookingAsAdmin = (token: string, id: string, reason: string) =>
  intervene(token, `/admin/support/bookings/${id}/cancel`, reason);

export const cancelTripAsAdmin = (token: string, id: string, reason: string) =>
  intervene(token, `/admin/support/trips/${id}/cancel`, reason);

export const suspendDriverAsAdmin = (token: string, profileId: string, reason: string) =>
  intervene(token, `/admin/support/drivers/${profileId}/suspend`, reason);

export const unsuspendDriverAsAdmin = (token: string, profileId: string, reason: string) =>
  intervene(token, `/admin/support/drivers/${profileId}/unsuspend`, reason);

export const voidNoShowFromSupport = (token: string, recordId: string, reason: string) =>
  intervene(token, `/admin/support/no-shows/${recordId}/void`, reason);

export const liftBlockFromSupport = (token: string, riderId: string, reason: string) =>
  intervene(token, `/admin/support/riders/${riderId}/lift-block`, reason);
