"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { getAuthToken, clearAuthCookie } from "@/lib/auth-cookie";
import { ApiError, createCorridor, updateCorridor } from "@/lib/backend";
import type { Corridor } from "@/lib/types";

type ActionResult<T> = { ok: true; data: T } | { ok: false; message: string };

async function requireToken(): Promise<string> {
  const token = await getAuthToken();
  if (!token) {
    redirect("/login");
  }
  return token;
}

export async function logoutAction(): Promise<void> {
  await clearAuthCookie();
  redirect("/login");
}

export async function createCorridorAction(input: {
  originCity: string;
  destCity: string;
  suggestedPricePerSeat: number;
  minPricePerSeat: number;
  maxPricePerSeat: number;
}): Promise<ActionResult<Corridor>> {
  const token = await requireToken();
  try {
    const corridor = await createCorridor(token, input);
    revalidatePath("/corridors");
    return { ok: true, data: corridor };
  } catch (err) {
    if (err instanceof ApiError) {
      if (err.statusCode === 401) await clearAuthCookie();
      return { ok: false, message: err.message };
    }
    return { ok: false, message: "حدث خطأ غير متوقع." };
  }
}

export async function updateCorridorAction(
  id: string,
  input: Partial<{
    originCity: string;
    destCity: string;
    suggestedPricePerSeat: number;
    minPricePerSeat: number;
    maxPricePerSeat: number;
    active: boolean;
  }>,
): Promise<ActionResult<Corridor>> {
  const token = await requireToken();
  try {
    const corridor = await updateCorridor(token, id, input);
    revalidatePath("/corridors");
    return { ok: true, data: corridor };
  } catch (err) {
    if (err instanceof ApiError) {
      if (err.statusCode === 401) await clearAuthCookie();
      return { ok: false, message: err.message };
    }
    return { ok: false, message: "حدث خطأ غير متوقع." };
  }
}

export async function toggleCorridorActiveAction(
  id: string,
  active: boolean,
): Promise<ActionResult<Corridor>> {
  return updateCorridorAction(id, { active });
}
