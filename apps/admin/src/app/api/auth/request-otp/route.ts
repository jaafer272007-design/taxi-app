import { NextResponse } from "next/server";

import { ApiError, requestOtp } from "@/lib/backend";

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const phone = typeof body?.phone === "string" ? body.phone : "";

  if (!phone.trim()) {
    return NextResponse.json({ message: "رقم الهاتف مطلوب." }, { status: 400 });
  }

  try {
    await requestOtp(phone);
    return NextResponse.json({ ok: true });
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
