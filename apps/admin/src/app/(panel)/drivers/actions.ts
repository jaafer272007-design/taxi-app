"use server";

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/admin-session";
import { clearAuthCookie } from "@/lib/auth-cookie";
import { ApiError, approveDriver, rejectDriver, suspendDriver } from "@/lib/backend";

export type ActionResult = { ok: true } | { ok: false; message: string };

/**
 * Every action re-resolves the session itself.
 *
 * A Server Action is a POST endpoint reachable by anyone who can send the
 * request — the fact that the page it lives on is only rendered for admins is a
 * UI decision, not a security boundary. The backend's RolesGuard is the real
 * one; this makes the panel fail cleanly instead of relaying an anonymous call.
 */
async function run(fn: (token: string) => Promise<unknown>): Promise<ActionResult> {
  const { token } = await requireAdmin();
  try {
    await fn(token);
    revalidatePath("/drivers");
    revalidatePath("/dashboard");
    return { ok: true };
  } catch (err) {
    if (err instanceof ApiError) {
      if (err.statusCode === 401) await clearAuthCookie();
      return { ok: false, message: err.message };
    }
    return { ok: false, message: "حدث خطأ غير متوقع." };
  }
}

export async function approveDriverAction(id: string): Promise<ActionResult> {
  return run((token) => approveDriver(token, id));
}

export async function rejectDriverAction(id: string, reason: string): Promise<ActionResult> {
  const trimmed = reason.trim();
  if (trimmed.length < 3) {
    // A rejection without a reason is a dead end for the driver: they get a
    // "rejected" screen with nothing to fix.
    return { ok: false, message: "اكتب سبب الرفض ليتمكّن السائق من تصحيحه." };
  }
  return run((token) => rejectDriver(token, id, trimmed));
}

export async function suspendDriverAction(id: string): Promise<ActionResult> {
  return run((token) => suspendDriver(token, id));
}
