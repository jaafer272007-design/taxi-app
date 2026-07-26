import { NextResponse } from "next/server";

import { setAuthCookie } from "@/lib/auth-cookie";
import { ApiError, verifyOtp } from "@/lib/backend";

/**
 * This is the ONLY place role gating happens client-adjacent: even though the
 * backend already refuses non-admin actions on every /corridors write (the
 * real, tested authorization boundary), we ALSO refuse to hand out an admin
 * session cookie to a non-admin phone number, so a normal rider/driver never
 * even sees the shell of this app after logging in.
 */
export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const phone = typeof body?.phone === "string" ? body.phone : "";
  const code = typeof body?.code === "string" ? body.code : "";

  if (!phone.trim() || !code.trim()) {
    return NextResponse.json(
      { message: "رقم الهاتف ورمز التحقق مطلوبان." },
      { status: 400 },
    );
  }

  try {
    const session = await verifyOtp(phone, code);

    if (!session.user.roles.includes("ADMIN")) {
      return NextResponse.json(
        { message: "هذا الحساب غير مخوّل بالدخول إلى لوحة التحكم." },
        { status: 403 },
      );
    }

    await setAuthCookie(session.accessToken);
    return NextResponse.json({ ok: true, user: session.user });
  } catch (err) {
    if (err instanceof ApiError) {
      return NextResponse.json(
        { message: err.message },
        { status: err.statusCode ?? 500 },
      );
    }
    return NextResponse.json({ message: "حدث خطأ غير متوقع." }, { status: 500 });
  }
}
