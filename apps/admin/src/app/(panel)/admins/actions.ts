"use server";

import { revalidatePath } from "next/cache";

import { requireSuperAdmin } from "@/lib/admin-session";
import { clearAuthCookie } from "@/lib/auth-cookie";
import { ApiError, createAdmin, resetAdminPassword, setAdminActive } from "@/lib/backend";

export type ActionResult = { ok: true } | { ok: false; message: string };

/**
 * Admin-account management. Every action calls `requireSuperAdmin()` itself.
 *
 * A Server Action is a POST endpoint anyone can reach — hiding the nav item
 * from a normal ADMIN is cosmetic, and not rendering the page is a UI
 * decision, not a security boundary. Two independent checks stand behind these:
 * this one, and the backend's `SuperAdminGuard`, which 403s a normal admin
 * whatever the panel believes.
 */
async function run(fn: (token: string) => Promise<unknown>, path = "/admins"): Promise<ActionResult> {
  const { token } = await requireSuperAdmin();
  try {
    await fn(token);
    revalidatePath(path);
    return { ok: true };
  } catch (err) {
    if (err instanceof ApiError) {
      if (err.statusCode === 401) await clearAuthCookie();
      return { ok: false, message: err.message };
    }
    return { ok: false, message: "حدث خطأ غير متوقع." };
  }
}

export async function createAdminAction(input: {
  username: string;
  password: string;
}): Promise<ActionResult> {
  const username = input.username.trim();
  if (username.length < 3) {
    return { ok: false, message: "اسم المستخدم يجب أن يكون 3 أحرف على الأقل." };
  }
  if (input.password.length < 10) {
    return { ok: false, message: "كلمة المرور يجب أن تكون 10 أحرف على الأقل." };
  }
  return run((token) => createAdmin(token, { username, password: input.password }));
}

export async function setAdminActiveAction(id: string, active: boolean): Promise<ActionResult> {
  return run((token) => setAdminActive(token, id, active));
}

export async function resetAdminPasswordAction(
  id: string,
  password: string,
): Promise<ActionResult> {
  if (password.length < 10) {
    return { ok: false, message: "كلمة المرور يجب أن تكون 10 أحرف على الأقل." };
  }
  return run((token) => resetAdminPassword(token, id, password));
}
