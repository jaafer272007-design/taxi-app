"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, ShieldCheck } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { normalizeIraqiPhone } from "@/lib/iraqi-phone";

type Step = "phone" | "otp";

export default function LoginPage() {
  const router = useRouter();
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submitPhone(e: React.FormEvent) {
    e.preventDefault();
    const normalized = normalizeIraqiPhone(phone);
    if (!normalized) {
      setError("أدخل رقم موبايل عراقي صحيح (مثال: 07701234567).");
      return;
    }
    setError(null);
    setBusy(true);
    try {
      const res = await fetch("/api/auth/request-otp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone: normalized }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.message ?? "تعذّر إرسال رمز التحقق.");
        return;
      }
      setPhone(normalized);
      setStep("otp");
    } catch {
      setError("تعذّر الاتصال بالخادم. تحقّق من الاتصال وحاول مرة أخرى.");
    } finally {
      setBusy(false);
    }
  }

  async function submitCode(e: React.FormEvent) {
    e.preventDefault();
    if (code.trim().length < 4) {
      setError("أدخل رمز التحقق المُرسَل إليك.");
      return;
    }
    setError(null);
    setBusy(true);
    try {
      const res = await fetch("/api/auth/verify-otp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone, code: code.trim() }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.message ?? "تعذّر التحقق من الرمز.");
        return;
      }
      toast.success("تم تسجيل الدخول");
      router.push("/corridors");
      router.refresh();
    } catch {
      setError("تعذّر الاتصال بالخادم. تحقّق من الاتصال وحاول مرة أخرى.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-background p-4">
      <Card className="w-full max-w-sm">
        <CardHeader className="items-center text-center">
          <div className="mb-2 flex size-12 items-center justify-center rounded-full bg-primary/10 text-primary">
            <ShieldCheck className="size-6" />
          </div>
          <CardTitle>لوحة تحكم — تكسي</CardTitle>
          <CardDescription>
            {step === "phone" ? (
              "سجّل الدخول برقم الأدمن لإدارة الممرات والتسعير."
            ) : (
              <>
                أدخل رمز التحقق المُرسَل إلى{" "}
                <span dir="ltr">{phone}</span>
              </>
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {step === "phone" ? (
            <form onSubmit={submitPhone} className="grid gap-4">
              <div className="grid gap-2">
                <Label htmlFor="phone">رقم الموبايل</Label>
                <Input
                  id="phone"
                  type="tel"
                  inputMode="tel"
                  autoComplete="tel"
                  placeholder="07701234567"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  disabled={busy}
                  dir="ltr"
                  className="text-start"
                />
              </div>
              {error && (
                <p role="alert" className="text-sm font-medium text-destructive">
                  {error}
                </p>
              )}
              <Button type="submit" disabled={busy} className="w-full">
                {busy && <Loader2 className="size-4 animate-spin" />}
                إرسال رمز التحقق
              </Button>
            </form>
          ) : (
            <form onSubmit={submitCode} className="grid gap-4">
              <div className="grid gap-2">
                <Label htmlFor="code">رمز التحقق</Label>
                <Input
                  id="code"
                  type="text"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  placeholder="123456"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  disabled={busy}
                  dir="ltr"
                  className="text-center tracking-[0.3em]"
                  maxLength={6}
                />
              </div>
              {error && (
                <p role="alert" className="text-sm font-medium text-destructive">
                  {error}
                </p>
              )}
              <Button type="submit" disabled={busy} className="w-full">
                {busy && <Loader2 className="size-4 animate-spin" />}
                تأكيد
              </Button>
              <Button
                type="button"
                variant="ghost"
                disabled={busy}
                onClick={() => {
                  setStep("phone");
                  setCode("");
                  setError(null);
                }}
                className="w-full"
              >
                تغيير الرقم
              </Button>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
