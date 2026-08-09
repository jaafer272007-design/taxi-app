import type { DriverStatus } from "./types";

/**
 * Arabic labels for backend enums.
 *
 * One definition, because these are what the admin READS — a status that says
 * «معتمد» on one screen and «مقبول» on another reads as two different states.
 * A raw English enum on screen is a bug (`e2e/drivers.spec.ts` asserts it).
 */
export const DRIVER_STATUS_AR: Record<DriverStatus, string> = {
  PENDING: "بانتظار المراجعة",
  APPROVED: "معتمد",
  SUSPENDED: "موقوف",
  REJECTED: "مرفوض",
};

export const DOC_TYPE_AR: Record<string, string> = {
  NATIONAL_ID: "الهوية",
  DRIVING_LICENSE: "إجازة السوق",
  VEHICLE_REG: "سنوية المركبة",
};

export const DOC_STATUS_AR: Record<string, string> = {
  PENDING: "بانتظار المراجعة",
  APPROVED: "مقبولة",
  REJECTED: "مرفوضة",
};

/** Booking lifecycle, as the rider's app words it. */
export const BOOKING_STATUS_AR: Record<string, string> = {
  CONFIRMED: "مؤكد",
  ONBOARD: "على متن الرحلة",
  COMPLETED: "مكتمل",
  CANCELLED: "ملغى",
  NO_SHOW: "لم يحضر",
};

export const TRIP_STATUS_AR: Record<string, string> = {
  OPEN: "مفتوحة",
  LOCKED: "مقفلة",
  EN_ROUTE: "جارية",
  COMPLETED: "مكتملة",
  SETTLED: "مُسوّاة",
  CANCELLED: "ملغاة",
};

/** What each recorded admin intervention was. */
export const ADMIN_ACTION_AR: Record<string, string> = {
  BOOKING_CANCELLED: "إلغاء حجز",
  TRIP_CANCELLED: "إلغاء رحلة",
  DRIVER_SUSPENDED: "إيقاف سائق",
  DRIVER_UNSUSPENDED: "رفع إيقاف سائق",
  NO_SHOW_VOIDED: "إلغاء واقعة عدم حضور",
  NO_SHOW_BLOCK_LIFTED: "رفع إيقاف راكب",
};

export const ENTITY_TYPE_AR: Record<string, string> = {
  BOOKING: "حجز",
  TRIP: "رحلة",
  DRIVER: "سائق",
  RIDER: "راكب",
};
