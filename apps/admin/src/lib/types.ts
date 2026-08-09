/**
 * A corridor (one direction). The admin does NOT set the fare — the driver does
 * when posting a trip. What lives here is the suggestion drivers see prefilled
 * and the band their price has to fall inside. The API guarantees
 * `0 < min <= suggested <= max`.
 */
export interface Corridor {
  id: string;
  originCity: string;
  destCity: string;
  active: boolean;
  suggestedPricePerSeat: number;
  minPricePerSeat: number;
  maxPricePerSeat: number;
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

// ── No-shows ─────────────────────────────────────────────────────────────

/** The policy numbers in force, sent with every no-show payload. */
export interface NoShowPolicy {
  threshold: number;
  windowDays: number;
  blockDays: number;
}

/** A rider currently blocked from making new bookings. */
export interface BlockedRider {
  riderId: string | null;
  name: string | null;
  phone: string | null;
  noShowCount: number;
  blockedUntil: string | null;
}

export interface BlockedRidersPayload {
  policy: NoShowPolicy;
  riders: BlockedRider[];
}

/**
 * One recorded no-show. A voided record KEEPS its row — the reason and the
 * admin who decided are the audit trail, so the panel shows them rather than
 * hiding the record.
 */
export interface NoShowRecord {
  id: string;
  riderId: string;
  tripId: string;
  bookingId: string;
  seatCount: number;
  createdAt: string;
  voidedAt: string | null;
  voidedBy: string | null;
  voidReason: string | null;
}

export interface RiderNoShowHistory {
  policy: NoShowPolicy;
  blocked: boolean;
  noShowCount: number;
  blockedUntil: string | null;
  records: NoShowRecord[];
}

// ── Support tools ────────────────────────────────────────────────────────

/** What the one search box resolved to. */
export type SupportSearchResult =
  | { kind: "EMPTY" }
  | { kind: "NOT_FOUND"; searchedPhone?: string }
  | { kind: "USER"; user: SupportUser; driverProfileId: string | null }
  | { kind: "TRIP"; tripId: string }
  | { kind: "BOOKING"; bookingId: string; tripId: string };

/**
 * A user as the support tools return them.
 *
 * Note what is NOT here: `emergencyContactName` / `emergencyContactPhone`.
 * That is the rider's own private data and no support task needs it — the
 * backend never selects it into any of these payloads, and
 * `admin-support.int-spec.ts` asserts that by searching the serialised text.
 */
export interface SupportUser {
  id: string;
  phone: string;
  name: string | null;
  gender: "MALE" | "FEMALE" | null;
  roles: string[];
  createdAt: string;
}

export interface SupportBooking {
  id: string;
  tripId: string;
  status: string;
  seatCount: number;
  fare: number;
  paymentStatus: string;
  createdAt: string;
  pickupLabel: string;
  dropoffLabel: string;
  trip: {
    status: string;
    departureTime: string;
    originCity: string;
    destCity: string;
  };
}

export interface SupportRating {
  id: string;
  tripId: string;
  fromUserId: string;
  toUserId: string;
  score: number;
  comment: string | null;
  createdAt: string;
}

export interface RiderSupportView {
  user: SupportUser;
  bookings: SupportBooking[];
  ratingsGiven: SupportRating[];
  ratingsReceived: SupportRating[];
  noShows: NoShowRecord[];
  block: { blocked: boolean; blockedUntil: string | null; countInWindow: number };
  policy: NoShowPolicy;
}

export interface DriverSupportView {
  profile: {
    id: string;
    status: DriverStatus;
    rejectionReason: string | null;
    ratingAvg: number;
    tripsDone: number;
    user: SupportUser;
    vehicle: {
      make: string;
      model: string;
      plate: string;
      color: string;
      seats: number;
    } | null;
    documents: { id: string; type: string; status: string; url: string }[];
  };
  trips: {
    id: string;
    status: string;
    departureTime: string;
    seatsTotal: number;
    seatsAvailable: number;
    pricePerSeat: number;
    bookingCount: number;
    originCity: string;
    destCity: string;
  }[];
  earnings: { total: number; collected: number };
  ratingsReceived: SupportRating[];
}

export interface TripSupportView {
  trip: {
    id: string;
    status: string;
    departureTime: string;
    departNow: boolean;
    seatsTotal: number;
    seatsAvailable: number;
    pricePerSeat: number;
    tripType: string;
    createdAt: string;
    originCity: string;
    destCity: string;
  };
  driver: {
    id: string;
    status: DriverStatus;
    ratingAvg: number;
    user: SupportUser;
  } | null;
  vehicle: { make: string; model: string; plate: string; color: string } | null;
  bookings: {
    id: string;
    status: string;
    seatCount: number;
    fare: number;
    paymentStatus: string;
    createdAt: string;
    pickupLabel: string;
    dropoffLabel: string;
    rider: { id: string; name: string | null; phone: string } | null;
  }[];
  adminActions: AdminAction[];
}

export type AdminActionType =
  | "BOOKING_CANCELLED"
  | "TRIP_CANCELLED"
  | "DRIVER_SUSPENDED"
  | "DRIVER_UNSUSPENDED"
  | "NO_SHOW_VOIDED"
  | "NO_SHOW_BLOCK_LIFTED";

export interface AdminAction {
  id: string;
  adminId: string;
  /** Copied at write time, so the row stays readable after the account is gone. */
  adminUsername: string;
  type: AdminActionType;
  entityType: string;
  entityId: string;
  reason: string;
  createdAt: string;
}
