"use server";

import { redirect } from "next/navigation";

import { clearAuthCookie } from "@/lib/auth-cookie";

export async function logoutAction(): Promise<void> {
  await clearAuthCookie();
  redirect("/login");
}
