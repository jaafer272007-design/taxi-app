import { NextResponse } from "next/server";

import { getAuthToken } from "@/lib/auth-cookie";

const API_BASE_URL = process.env.API_BASE_URL ?? "http://localhost:3000";

/**
 * Streams a driver's uploaded document through to the browser.
 *
 * The proxy exists because the admin JWT lives in an **httpOnly** cookie: the
 * browser deliberately cannot read it, so an `<img src>` or a new tab can never
 * attach the `Authorization: Bearer` header the backend requires. This handler
 * runs server-side, reads the cookie, and forwards the request with the header
 * attached.
 *
 * It adds no authorization of its own and must not: the backend's
 * `DocumentsService.authorizeAccess` is the boundary (owning driver or ADMIN),
 * and its 403/404 are passed straight through. This handler only lends the
 * caller's own credentials to a request they are already making.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const token = await getAuthToken();
  if (!token) {
    return NextResponse.json({ message: "انتهت الجلسة. سجّل الدخول من جديد." }, { status: 401 });
  }

  let upstream: Response;
  try {
    upstream = await fetch(`${API_BASE_URL}/documents/${encodeURIComponent(id)}`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store",
    });
  } catch {
    return NextResponse.json({ message: "تعذّر الاتصال بالخادم." }, { status: 502 });
  }

  if (!upstream.ok || !upstream.body) {
    return NextResponse.json(
      { message: upstream.status === 404 ? "المستند غير موجود." : "تعذّر عرض المستند." },
      { status: upstream.status },
    );
  }

  return new NextResponse(upstream.body, {
    status: upstream.status,
    headers: {
      "Content-Type": upstream.headers.get("Content-Type") ?? "application/octet-stream",
      // `inline` so a scanned ID opens in the tab rather than downloading, but
      // `nosniff` so a mislabelled upload can't be coaxed into executing as
      // something else in the admin's session.
      "Content-Disposition": upstream.headers.get("Content-Disposition") ?? "inline",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, no-store",
    },
  });
}
