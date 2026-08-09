"use server";

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/admin-session";
import { clearAuthCookie } from "@/lib/auth-cookie";
import {
  ApiError,
  cancelBookingAsAdmin,
  cancelTripAsAdmin,
  liftBlockFromSupport,
  suspendDriverAsAdmin,
  unsuspendDriverAsAdmin,
  voidNoShowFromSupport,
} from "@/lib/backend";

export type ActionResult = { ok: true } | { ok: false; message: string };

/**
 * Every intervention goes through here.
 *
 * Same posture as the driver and no-show actions: the session is re-resolved
 * on each call, because a Server Action is a POST endpoint anyone can reach
 * and "the page is admin-only" is a UI fact, not a boundary. The backend's
 * RolesGuard is the real gate — and the acting admin recorded in the audit log
 * comes from the JWT there, never from anything sent here.
 */
async function run(fn: (token: string) => Promise<unknown>): Promise<ActionResult> {
  const { token } = await requireAdmin();
  try {
    await fn(token);
    revalidatePath("/support");
    revalidatePath("/actions");
    return { ok: true };
  } catch (err) {
    if (err instanceof ApiError) {
      if (err.statusCode === 401) await clearAuthCookie();
      return { ok: false, message: err.message };
    }
    return { ok: false, message: "حدث خطأ غير متوقع." };
  }
}

/**
 * The reason is checked here as well as by the backend DTO.
 *
 * Not belt-and-braces: an intervention changes someone's trip or a driver's
 * income and may be reviewed weeks later. The reason written at the moment of
 * the action is the only thing that will still exist.
 */
function requireReason(reason: string): string | null {
  const trimmed = reason.trim();
  return trimmed.length >= 3 ? trimmed : null;
}

const REASON_REQUIRED = "اكتب سبباً واضحاً (٣ أحرف على الأقل).";

export async function cancelBookingAction(id: string, reason: string): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: REASON_REQUIRED };
  return run((t) => cancelBookingAsAdmin(t, id, trimmed));
}

export async function cancelTripAction(id: string, reason: string): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: REASON_REQUIRED };
  return run((t) => cancelTripAsAdmin(t, id, trimmed));
}

export async function suspendDriverAction(
  profileId: string,
  reason: string,
): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: REASON_REQUIRED };
  return run((t) => suspendDriverAsAdmin(t, profileId, trimmed));
}

export async function unsuspendDriverAction(
  profileId: string,
  reason: string,
): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: REASON_REQUIRED };
  return run((t) => unsuspendDriverAsAdmin(t, profileId, trimmed));
}

export async function voidNoShowAction(recordId: string, reason: string): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: REASON_REQUIRED };
  return run((t) => voidNoShowFromSupport(t, recordId, trimmed));
}

export async function liftBlockAction(riderId: string, reason: string): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: REASON_REQUIRED };
  return run((t) => liftBlockFromSupport(t, riderId, trimmed));
}
