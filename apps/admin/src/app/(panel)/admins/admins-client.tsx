"use client";

import { useState, useTransition } from "react";
import { KeyRound, Loader2, Plus, ShieldCheck } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDate } from "@/lib/format";
import type { AdminAccount } from "@/lib/types";
import { createAdminAction, resetAdminPasswordAction, setAdminActiveAction } from "./actions";

/** Mirrors PasswordService.MIN_LENGTH on the backend. */
const MIN_PASSWORD_LENGTH = 10;

export function AdminsClient({
  admins,
  currentAdminId,
}: {
  admins: AdminAccount[];
  currentAdminId: string;
}) {
  const [pending, startTransition] = useTransition();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [resetting, setResetting] = useState<AdminAccount | null>(null);

  const [newUsername, setNewUsername] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [resetPassword, setResetPassword] = useState("");

  function submitCreate() {
    startTransition(async () => {
      const result = await createAdminAction({
        username: newUsername,
        password: newPassword,
      });
      if (!result.ok) {
        toast.error(result.message);
        return;
      }
      // Clear the password out of component state as soon as it has been sent.
      setNewUsername("");
      setNewPassword("");
      setCreating(false);
      toast.success("تم إنشاء حساب المدير.");
    });
  }

  function submitReset() {
    const target = resetting;
    if (!target) return;
    startTransition(async () => {
      const result = await resetAdminPasswordAction(target.id, resetPassword);
      if (!result.ok) {
        toast.error(result.message);
        return;
      }
      setResetPassword("");
      setResetting(null);
      toast.success(`تم تعيين كلمة مرور جديدة لـ ${target.username}. سلّمها له مباشرة.`);
    });
  }

  function toggleActive(admin: AdminAccount, next: boolean) {
    setBusyId(admin.id);
    startTransition(async () => {
      const result = await setAdminActiveAction(admin.id, next);
      setBusyId(null);
      if (!result.ok) {
        toast.error(result.message);
        return;
      }
      toast.success(next ? "تم تفعيل الحساب." : "تم تعطيل الحساب.");
    });
  }

  return (
    <div className="grid gap-6">
      <header className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">إدارة المدراء</h1>
          <p className="text-sm text-muted-foreground">
            المدير العادي يملك كل صلاحيات التشغيل — الممرات، اعتماد السائقين، لوحة
            المعلومات. هذه الصفحة وحدها مخصّصة للمدير الأعلى.
          </p>
        </div>
        <Button
          onClick={() => {
            setNewUsername("");
            setNewPassword("");
            setCreating(true);
          }}
        >
          <Plus className="size-4" />
          أضف مديراً
        </Button>
      </header>

      <div className="overflow-hidden rounded-xl border border-border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>اسم المستخدم</TableHead>
              <TableHead>الدور</TableHead>
              <TableHead>أُنشئ</TableHead>
              <TableHead>مفعّل</TableHead>
              <TableHead className="text-end">كلمة المرور</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {admins.map((admin) => {
              const isSuper = admin.role === "SUPER_ADMIN";
              const isSelf = admin.id === currentAdminId;
              return (
                <TableRow key={admin.id}>
                  <TableCell className="font-medium" dir="ltr">
                    {admin.username}
                  </TableCell>
                  <TableCell>
                    {isSuper ? (
                      <Badge className="border-0 bg-accent text-accent-foreground">
                        <ShieldCheck className="size-3.5" />
                        مدير أعلى
                      </Badge>
                    ) : (
                      <Badge className="border-0 bg-secondary text-secondary-foreground">
                        مدير
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {formatDate(admin.createdAt)}
                  </TableCell>
                  <TableCell>
                    {/* The super admin cannot be disabled — there would be no
                        way back into admin management without a DB console. */}
                    <Switch
                      checked={admin.active}
                      disabled={isSuper || isSelf || (busyId === admin.id && pending)}
                      onCheckedChange={(next) => toggleActive(admin, next)}
                      aria-label={`تفعيل ${admin.username}`}
                    />
                  </TableCell>
                  <TableCell className="text-end">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setResetPassword("");
                        setResetting(admin);
                      }}
                    >
                      <KeyRound className="size-4" />
                      إعادة تعيين
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>

      {/* ── Create ────────────────────────────────────────────────────── */}
      <Dialog open={creating} onOpenChange={setCreating}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>حساب مدير جديد</DialogTitle>
            <DialogDescription>
              يحصل على كل صلاحيات التشغيل، لكن لا يرى هذه الصفحة ولا يقدر يدير
              المدراء.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="new-username">اسم المستخدم</Label>
              {/* Western + LTR: a username is typed on a login form and read
                  aloud when handed over, so it stays in Latin characters. */}
              <Input
                id="new-username"
                dir="ltr"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                value={newUsername}
                onChange={(e) => setNewUsername(e.target.value)}
                placeholder="zainab"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="new-password">كلمة المرور</Label>
              <Input
                id="new-password"
                type="password"
                dir="ltr"
                autoComplete="new-password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                {MIN_PASSWORD_LENGTH} أحرف على الأقل. سلّمها للمدير مباشرة — لا
                يمكن عرضها مرة أخرى بعد الحفظ.
              </p>
            </div>
          </div>

          <DialogFooter>
            <Button variant="ghost" onClick={() => setCreating(false)}>
              إلغاء
            </Button>
            <Button onClick={submitCreate} disabled={pending}>
              {pending && <Loader2 className="size-4 animate-spin" />}
              إنشاء
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Reset password ────────────────────────────────────────────── */}
      <Dialog open={resetting !== null} onOpenChange={(open) => !open && setResetting(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>إعادة تعيين كلمة المرور</DialogTitle>
            <DialogDescription>
              كلمة مرور جديدة لـ <span dir="ltr">{resetting?.username}</span>. لا
              يمكن استرجاع القديمة — تُخزَّن مشفّرة ولا يستطيع أحد قراءتها.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <Label htmlFor="reset-password">كلمة المرور الجديدة</Label>
            <Input
              id="reset-password"
              type="password"
              dir="ltr"
              autoComplete="new-password"
              value={resetPassword}
              onChange={(e) => setResetPassword(e.target.value)}
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              {MIN_PASSWORD_LENGTH} أحرف على الأقل.
            </p>
          </div>

          <DialogFooter>
            <Button variant="ghost" onClick={() => setResetting(null)}>
              إلغاء
            </Button>
            <Button onClick={submitReset} disabled={pending}>
              {pending && <Loader2 className="size-4 animate-spin" />}
              حفظ
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
