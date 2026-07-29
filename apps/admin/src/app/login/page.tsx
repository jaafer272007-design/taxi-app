"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, ShieldCheck, TriangleAlert } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

/**
 * Admin login — username + password.
 *
 * Deliberately NOT the rider/driver WhatsApp OTP flow: admins are a small
 * internal group, and OTP delivery is still blocked on WhatsApp credentials.
 *
 * Both fields keep **Western digits**: they are inputs, and a password has to
 * round-trip byte for byte. The locked Arabic-Indic rule applies to displayed
 * values, not to what a keyboard produces.
 *
 * The error text is whatever the backend returned, verbatim. That is
 * deliberate: the backend gives the same sentence for "no such username" and
 * "wrong password" so neither can be used to enumerate accounts, and rewording
 * it here would risk reintroducing the distinction.
 */
export default function LoginPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!username.trim() || !password) {
      setError("أدخل اسم المستخدم وكلمة المرور.");
      return;
    }
    setError(null);
    setBusy(true);
    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: username.trim(), password }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(data.message ?? "تعذّر تسجيل الدخول.");
        return;
      }
      // Drop the password from component state rather than leaving it in
      // memory behind the redirect.
      setPassword("");
      router.replace("/dashboard");
      router.refresh();
    } catch {
      setError("تعذّر الاتصال بالخادم. تحقّق من الاتصال وحاول مرة أخرى.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-dvh items-center justify-center bg-background p-6">
      <Card className="w-full max-w-sm">
        <CardHeader className="text-center">
          <div className="mx-auto mb-2 flex size-12 items-center justify-center rounded-2xl bg-accent text-accent-foreground">
            <ShieldCheck className="size-6" />
          </div>
          <CardTitle>لوحة تحكم — تكسي</CardTitle>
          <CardDescription>سجّل الدخول باسم المستخدم وكلمة المرور.</CardDescription>
        </CardHeader>

        <CardContent>
          <form onSubmit={submit} className="space-y-4" noValidate>
            <div className="space-y-2">
              <Label htmlFor="username">اسم المستخدم</Label>
              <Input
                id="username"
                name="username"
                dir="ltr"
                autoComplete="username"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                value={username}
                onChange={(e) => {
                  setUsername(e.target.value);
                  if (error) setError(null);
                }}
                disabled={busy}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">كلمة المرور</Label>
              <Input
                id="password"
                name="password"
                type="password"
                dir="ltr"
                autoComplete="current-password"
                value={password}
                onChange={(e) => {
                  setPassword(e.target.value);
                  if (error) setError(null);
                }}
                disabled={busy}
                required
              />
            </div>

            {error && (
              <p
                role="alert"
                className="flex items-start gap-2 rounded-lg bg-destructive-tonal p-3 text-sm text-destructive"
              >
                <TriangleAlert className="mt-0.5 size-4 shrink-0" />
                <span>{error}</span>
              </p>
            )}

            <Button type="submit" className="w-full" disabled={busy}>
              {busy && <Loader2 className="size-4 animate-spin" />}
              دخول
            </Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
