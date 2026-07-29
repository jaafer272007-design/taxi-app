/**
 * A user-facing API error — `message` is always a ready-to-show Arabic
 * string. Mirrors `packages/shared/lib/net/api_exception.dart`'s
 * `ApiException` + `_serverMessage`, so all three apps (rider, driver, admin)
 * surface backend errors identically.
 */
export class ApiError extends Error {
  readonly statusCode?: number;
  readonly isNetwork: boolean;

  constructor(message: string, opts?: { statusCode?: number; isNetwork?: boolean }) {
    super(message);
    this.name = "ApiError";
    this.statusCode = opts?.statusCode;
    this.isNetwork = opts?.isNetwork ?? false;
  }
}

/** Prefer the backend's Arabic message; fall back by status code. */
export function serverMessage(data: unknown, status?: number): string {
  if (data && typeof data === "object" && "message" in data) {
    const msg = (data as { message?: unknown }).message;
    if (typeof msg === "string" && msg.trim().length > 0) return msg;
    if (Array.isArray(msg) && msg.length > 0) return String(msg[0]);
  }
  switch (status) {
    case 401:
      return "انتهت الجلسة. سجّل الدخول من جديد.";
    case 403:
      return "ليس لديك صلاحية لهذا الإجراء.";
    case 404:
      return "غير موجود.";
    case 429:
      return "محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.";
    default:
      return "حدث خطأ غير متوقع. حاول مرة أخرى.";
  }
}
