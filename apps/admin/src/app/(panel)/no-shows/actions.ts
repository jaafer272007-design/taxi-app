"use server";

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/admin-session";
import { clearAuthCookie } from "@/lib/auth-cookie";
import { ApiError, liftRiderBlock, voidNoShow } from "@/lib/backend";

export type ActionResult = { ok: true } | { ok: false; message: string };

/**
 * Same posture as the driver actions: every action re-resolves the session,
 * because a Server Action is a POST endpoint anyone can reach and the page
 * being admin-only is a UI fact, not a boundary. The backend's RolesGuard is
 * the real gate.
 */
async function run(fn: (token: string) => Promise<unknown>): Promise<ActionResult> {
  const { token } = await requireAdmin();
  try {
    await fn(token);
    revalidatePath("/no-shows");
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
 * Not belt-and-braces for its own sake: this is the appeal path, and a decision
 * that lifts a penalty with no written reason cannot be reviewed later and
 * teaches the policy nothing about which cases it got wrong.
 */
function requireReason(reason: string): string | null {
  const trimmed = reason.trim();
  return trimmed.length >= 3 ? trimmed : null;
}

export async function voidNoShowAction(id: string, reason: string): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: "اكتب سبباً واضحاً (٣ أحرف على الأقل)." };
  return run((token) => voidNoShow(token, id, trimmed));
}

export async function liftBlockAction(riderId: string, reason: string): Promise<ActionResult> {
  const trimmed = requireReason(reason);
  if (!trimmed) return { ok: false, message: "اكتب سبباً واضحاً (٣ أحرف على الأقل)." };
  return run((token) => liftRiderBlock(token, riderId, trimmed));
}
