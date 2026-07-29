export interface Corridor {
  id: string;
  originCity: string;
  destCity: string;
  active: boolean;
  pricePerSeat: number;
}

// ── Admin accounts ───────────────────────────────────────────────────────

export type AdminRole = "SUPER_ADMIN" | "ADMIN";

/**
 * An admin account as the backend describes it. There is deliberately no
 * `passwordHash` field: the API never sends one, and this type makes that a
 * compile-time fact rather than a hope.
 */
export interface AdminAccount {
  id: string;
  username: string;
  role: AdminRole;
  active: boolean;
  createdAt: string;
  createdBy: string | null;
}

/** Who is logged in. From GET /admin/auth/me — never decoded client-side. */
export interface AdminMe {
  id: string;
  username: string;
  role: AdminRole;
}

export interface AdminSession {
  accessToken: string;
  admin: AdminAccount;
}

// ── Drivers ──────────────────────────────────────────────────────────────

export type DriverStatus = "PENDING" | "APPROVED" | "SUSPENDED" | "REJECTED";
export type DocType = "NATIONAL_ID" | "DRIVING_LICENSE" | "VEHICLE_REG";
export type DocStatus = "PENDING" | "APPROVED" | "REJECTED";

export interface DriverDocument {
  id: string;
  type: DocType;
  url: string;
  status: DocStatus;
}

export interface DriverVehicle {
  make: string;
  model: string;
  plate: string;
  color: string;
  seats: number;
}

export interface Driver {
  id: string;
  status: DriverStatus;
  rejectionReason: string | null;
  ratingAvg: number;
  tripsDone: number;
  user: { id: string; phone: string; name: string | null } | null;
  vehicle: DriverVehicle | null;
  documents: DriverDocument[];
}

// ── Dashboard ────────────────────────────────────────────────────────────

/**
 * The GET /admin/dashboard payload, mirroring `AdminService.getDashboard()`.
 *
 * Every field is optional. The panel renders a dash for anything missing rather
 * than `NaN`: a counter the backend stops sending should read as "unknown", not
 * as broken arithmetic on a money-adjacent screen.
 */
export interface DashboardCounts {
  riders?: number;
  drivers?: { total?: number; byStatus?: Record<string, number> };
  trips?: { total?: number; byStatus?: Record<string, number>; today?: number };
  bookings?: number;
  earningsTotal?: number;
}
