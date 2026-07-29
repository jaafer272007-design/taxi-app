import { NextResponse } from "next/server";

import { setAuthCookie } from "@/lib/auth-cookie";
import { ApiError, adminLogin } from "@/lib/backend";

/**
 * Username + password → httpOnly session cookie.
 *
 * A Route Handler rather than a Server Action so the browser never receives the
 * JWT: the token is exchanged server-to-server and written straight into a
 * cookie the page's JavaScript cannot read. Nothing in the response body
 * carries it.
 */
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ message: "طلب غير صالح." }, { status: 400 });
  }

  const { username, password } = (body ?? {}) as {
    username?: unknown;
    password?: unknown;
  };

  if (typeof username !== "string" || typeof password !== "string" || !username || !password) {
    return NextResponse.json(
      { message: "أدخل اسم المستخدم وكلمة المرور." },
      { status: 400 },
    );
  }

  try {
    const session = await adminLogin(username, password);
    await setAuthCookie(session.accessToken);
    // Only the role goes back — the panel needs it to decide the landing page.
    // The token stays in the cookie.
    return NextResponse.json({ role: session.admin.role });
  } catch (err) {
    if (err instanceof ApiError) {
      // The backend's message is already the generic Arabic one for a bad
      // credential and the rate-limit sentence for a lockout. Passing it
      // through unchanged is deliberate: rewriting it here risks reintroducing
      // the "no such user" / "wrong password" distinction the backend is
      // careful not to make.
      return NextResponse.json({ message: err.message }, { status: err.statusCode ?? 500 });
    }
    return NextResponse.json({ message: "حدث خطأ غير متوقع." }, { status: 500 });
  }
}
