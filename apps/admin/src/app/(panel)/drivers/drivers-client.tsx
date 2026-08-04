"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import {
  Check,
  ExternalLink,
  FileText,
  IdCard,
  Loader2,
  Pause,
  Star,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { formatRating, formatSeats, formatTrips } from "@/lib/format";
import type { DocStatus, DocType, Driver, DriverStatus } from "@/lib/types";
import { approveDriverAction, rejectDriverAction, suspendDriverAction } from "./actions";

const STATUS_LABEL: Record<DriverStatus, string> = {
  PENDING: "بانتظار المراجعة",
  APPROVED: "معتمد",
  SUSPENDED: "موقوف",
  REJECTED: "مرفوض",
};

const DOC_LABEL: Record<DocType, string> = {
  NATIONAL_ID: "الهوية",
  DRIVING_LICENSE: "إجازة السوق",
  VEHICLE_REG: "تسجيل المركبة",
};

const DOC_STATUS_LABEL: Record<DocStatus, string> = {
  PENDING: "قيد المراجعة",
  APPROVED: "مقبول",
  REJECTED: "مرفوض",
};

const FILTERS: { value: DriverStatus | "ALL"; label: string }[] = [
  { value: "ALL", label: "الكل" },
  { value: "PENDING", label: "بانتظار المراجعة" },
  { value: "APPROVED", label: "معتمدون" },
  { value: "SUSPENDED", label: "موقوفون" },
  { value: "REJECTED", label: "مرفوضون" },
];

function statusClasses(status: DriverStatus): string {
  // Opaque tonal fills, never an alpha wash: a translucent tint composites over
  // whatever is behind it and its measured contrast stops being predictable.
  switch (status) {
    case "APPROVED":
      return "bg-success-tonal text-success";
    case "PENDING":
      return "bg-warning-tonal text-warning";
    case "SUSPENDED":
      return "bg-info-tonal text-info";
    case "REJECTED":
      return "bg-destructive-tonal text-destructive";
  }
}

export function DriversClient({
  drivers,
  status,
}: {
  drivers: Driver[];
  status?: DriverStatus;
}) {
  const [pending, startTransition] = useTransition();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<Driver | null>(null);
  const [reason, setReason] = useState("");

  function act(id: string, fn: () => Promise<{ ok: boolean; message?: string }>, done: string) {
    setBusyId(id);
    startTransition(async () => {
      const result = await fn();
      setBusyId(null);
      if (!result.ok) {
        toast.error(result.message ?? "تعذّر تنفيذ العملية.");
        return;
      }
      toast.success(done);
    });
  }

  function submitRejection() {
    const driver = rejecting;
    if (!driver) return;
    const text = reason;
    setBusyId(driver.id);
    startTransition(async () => {
      const result = await rejectDriverAction(driver.id, text);
      setBusyId(null);
      if (!result.ok) {
        toast.error(result.message);
        return;
      }
      setRejecting(null);
      setReason("");
      toast.success("تم رفض الطلب وإشعار السائق بالسبب.");
    });
  }

  return (
    <div className="grid gap-6">
      <header>
        <h1 className="text-2xl font-bold">السائقون</h1>
        <p className="text-sm text-muted-foreground">
          راجع المستمسكات واعتمد السائق ليتمكّن من إعلان الرحلات.
        </p>
      </header>

      <nav className="flex flex-wrap gap-2">
        {FILTERS.map((f) => {
          const active = f.value === "ALL" ? !status : status === f.value;
          return (
            <Link
              key={f.value}
              href={f.value === "ALL" ? "/drivers" : `/drivers?status=${f.value}`}
              aria-current={active ? "page" : undefined}
              className={cn(
                "rounded-full border px-4 py-2 text-sm transition-colors",
                active
                  ? "border-foreground bg-foreground font-semibold text-background"
                  : "border-border bg-card text-muted-foreground hover:bg-accent",
              )}
            >
              {f.label}
            </Link>
          );
        })}
      </nav>

      {drivers.length === 0 ? (
        <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
          <div className="flex size-14 items-center justify-center rounded-full bg-accent text-accent-foreground">
            <IdCard className="size-6" />
          </div>
          <p className="font-medium">لا يوجد سائقون بهذه الحالة</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {drivers.map((driver) => {
            const busy = busyId === driver.id && pending;
            return (
              <Card key={driver.id}>
                <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
                  <div className="min-w-0">
                    <CardTitle className="truncate">
                      {driver.user?.name?.trim() || "سائق بلا اسم"}
                    </CardTitle>
                    <p className="mt-1 text-sm text-muted-foreground" dir="ltr">
                      {driver.user?.phone ?? "—"}
                    </p>
                  </div>
                  <Badge className={cn("shrink-0 border-0", statusClasses(driver.status))}>
                    {STATUS_LABEL[driver.status]}
                  </Badge>
                </CardHeader>

                <CardContent className="space-y-4">
                  <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <Star className="size-3.5" />
                      {formatRating(driver.ratingAvg)}
                    </span>
                    <span>{formatTrips(driver.tripsDone)}</span>
                    {driver.vehicle && (
                      <>
                        <span>
                          {driver.vehicle.make} {driver.vehicle.model} · {driver.vehicle.color} ·{" "}
                          <span dir="ltr">{driver.vehicle.plate}</span>
                        </span>
                        {/* The seat count is its OWN flex item, not appended to
                            the line after a `·`. In RTL the separator resolves
                            to the right of the digit — exactly where a `٠`
                            would sit — and Cairo draws `·` and `٠` as the same
                            small mid-height dot, so `· ٤ مقاعد` reads as
                            «٤٠ مقاعد»: forty seats instead of four. Measured in
                            Chromium, not assumed; see CLAUDE.md. Separation is
                            the parent's `gap-x-6`, so no character sits next to
                            the digit at all. */}
                        <span>{formatSeats(driver.vehicle.seats)}</span>
                      </>
                    )}
                  </div>

                  {driver.status === "REJECTED" && driver.rejectionReason && (
                    <p className="rounded-lg bg-destructive-tonal p-3 text-sm text-destructive">
                      سبب الرفض: {driver.rejectionReason}
                    </p>
                  )}

                  <div>
                    <p className="mb-2 text-xs font-semibold text-muted-foreground">
                      المستمسكات
                    </p>
                    {driver.documents.length === 0 ? (
                      <p className="text-sm text-muted-foreground">لم يرفع أي مستمسك بعد.</p>
                    ) : (
                      <ul className="grid gap-2 sm:grid-cols-3">
                        {driver.documents.map((doc) => (
                          <li key={doc.id}>
                            {/* Opens through the panel's own proxy route: the
                                JWT is httpOnly, so a direct backend link could
                                never carry the Authorization header. */}
                            <a
                              href={`/api/documents/${doc.id}`}
                              target="_blank"
                              rel="noreferrer"
                              className="flex items-center gap-2 rounded-lg border border-border bg-card p-3 text-sm transition-colors hover:bg-accent"
                            >
                              <FileText className="size-4 shrink-0 text-muted-foreground" />
                              <span className="min-w-0 flex-1">
                                <span className="block truncate font-medium">
                                  {DOC_LABEL[doc.type] ?? doc.type}
                                </span>
                                <span className="block text-xs text-muted-foreground">
                                  {DOC_STATUS_LABEL[doc.status] ?? doc.status}
                                </span>
                              </span>
                              <ExternalLink className="size-3.5 shrink-0 text-muted-foreground" />
                            </a>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>

                  <div className="flex flex-wrap gap-2">
                    {driver.status !== "APPROVED" && (
                      <Button
                        size="sm"
                        disabled={busy}
                        onClick={() =>
                          act(driver.id, () => approveDriverAction(driver.id), "تم اعتماد السائق.")
                        }
                      >
                        {busy ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
                        اعتماد
                      </Button>
                    )}
                    {driver.status !== "REJECTED" && (
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={busy}
                        onClick={() => {
                          setRejecting(driver);
                          setReason("");
                        }}
                      >
                        <X className="size-4" />
                        رفض
                      </Button>
                    )}
                    {driver.status === "APPROVED" && (
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={busy}
                        onClick={() =>
                          act(driver.id, () => suspendDriverAction(driver.id), "تم إيقاف السائق.")
                        }
                      >
                        <Pause className="size-4" />
                        إيقاف
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      <Dialog open={rejecting !== null} onOpenChange={(open) => !open && setRejecting(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>رفض طلب السائق</DialogTitle>
            <DialogDescription>
              يظهر السبب للسائق في تطبيقه ليصحّح المطلوب ويعيد الرفع — اكتبه بوضوح.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <Label htmlFor="reject-reason">سبب الرفض</Label>
            <Input
              id="reject-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="مثال: صورة إجازة السوق غير واضحة."
              autoFocus
            />
          </div>

          <DialogFooter>
            <Button variant="ghost" onClick={() => setRejecting(null)}>
              تراجع
            </Button>
            <Button variant="destructive" onClick={submitRejection} disabled={pending}>
              {pending && <Loader2 className="size-4 animate-spin" />}
              رفض الطلب
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
