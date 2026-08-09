"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { ShieldOff, TriangleAlert, Undo2 } from "lucide-react";

import { RefreshBar } from "@/components/refresh-bar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCount, formatDate } from "@/lib/format";
import type { BlockedRidersPayload, RiderNoShowHistory } from "@/lib/types";
import { liftBlockAction, voidNoShowAction } from "./actions";

/** How often the blocked list re-asks. */
const REFRESH_MS = 60_000;

/**
 * Blocked riders, and one rider's record beside them.
 *
 * ## Why a reason is mandatory on both actions
 *
 * Voiding a no-show and lifting a block both undo a penalty. The record keeps
 * the reason and the admin who made the call, which is what makes this an
 * appeal process rather than an override — and it is the only signal that ever
 * tells us the thresholds are wrong.
 */
export function NoShowsClient({
  payload,
  history,
  selectedRiderId,
}: {
  payload: BlockedRidersPayload;
  history: RiderNoShowHistory | null;
  selectedRiderId: string | null;
}) {
  const router = useRouter();
  const { policy, riders } = payload;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">عدم الحضور</h1>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
            الراكب الذي يحجز ولا يحضر يكلّف السائق مقعداً كاملاً بلا أجرة. السياسة
            الحالية: {formatCount(policy.threshold)} مرات خلال{" "}
            {formatCount(policy.windowDays)} يوماً توقف الحجز لمدة{" "}
            {formatCount(policy.blockDays)} أيام. الحجوزات القائمة لا تُلغى.
          </p>
        </div>
        <RefreshBar intervalMs={REFRESH_MS} />
      </div>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">
          الموقوفون حالياً{riders.length > 0 ? ` (${formatCount(riders.length)})` : ""}
        </h2>

        {riders.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border py-12 text-center text-sm text-muted-foreground">
            لا يوجد ركّاب موقوفون حالياً.
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الراكب</TableHead>
                  <TableHead>الهاتف</TableHead>
                  <TableHead>عدد المرات</TableHead>
                  <TableHead>ينتهي الإيقاف</TableHead>
                  <TableHead className="text-left">إجراء</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {riders.map((r, i) => (
                  // Stable key. `riderId` is nullable in the payload (a user row could
                  // have been removed), and a random key would remount the row on
                  // every render — so fall back to the position, not to chance.
                  <TableRow key={r.riderId ?? `row-${i}`}>
                    <TableCell className="font-medium">{r.name ?? "—"}</TableCell>
                    {/* A phone number is an identifier to be dialled, not a
                        quantity — Western digits, forced LTR (CLAUDE.md). */}
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {r.phone ?? "—"}
                    </TableCell>
                    <TableCell className="tabular-nums">{formatCount(r.noShowCount)}</TableCell>
                    <TableCell className="tabular-nums">
                      {r.blockedUntil ? formatDate(r.blockedUntil) : "—"}
                    </TableCell>
                    <TableCell className="text-left">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() =>
                          router.push(`/no-shows?rider=${encodeURIComponent(r.riderId ?? "")}`)
                        }
                        disabled={!r.riderId}
                      >
                        السجل
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </section>

      {selectedRiderId && history && (
        <RiderHistory riderId={selectedRiderId} history={history} />
      )}
    </div>
  );
}

function RiderHistory({
  riderId,
  history,
}: {
  riderId: string;
  history: RiderNoShowHistory;
}) {
  const [dialog, setDialog] = useState<
    { kind: "void"; id: string } | { kind: "lift" } | null
  >(null);

  const live = history.records.filter((r) => !r.voidedAt).length;

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">سجل الراكب</h2>
        <div className="flex items-center gap-2">
          {history.blocked ? (
            <Badge variant="destructive">
              موقوف حتى {history.blockedUntil ? formatDate(history.blockedUntil) : "—"}
            </Badge>
          ) : (
            <Badge variant="secondary">غير موقوف</Badge>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setDialog({ kind: "lift" })}
            disabled={live === 0}
          >
            <ShieldOff className="size-4" />
            ارفع الإيقاف
          </Button>
        </div>
      </div>

      {history.records.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border py-12 text-center text-sm text-muted-foreground">
          لا توجد وقائع مسجّلة لهذا الراكب.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>التاريخ</TableHead>
                <TableHead>المقاعد</TableHead>
                <TableHead>الحالة</TableHead>
                <TableHead>سبب الإلغاء</TableHead>
                <TableHead className="text-left">إجراء</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {history.records.map((r) => (
                <TableRow key={r.id} className={r.voidedAt ? "opacity-60" : undefined}>
                  <TableCell className="tabular-nums">{formatDate(r.createdAt)}</TableCell>
                  <TableCell className="tabular-nums">{formatCount(r.seatCount)}</TableCell>
                  <TableCell>
                    {r.voidedAt ? (
                      <Badge variant="secondary">ملغاة</Badge>
                    ) : (
                      <Badge variant="destructive">محتسبة</Badge>
                    )}
                  </TableCell>
                  {/* The reason stays visible on a voided row: it is the audit
                      trail, and hiding it would leave no trace that anyone
                      reviewed the case. */}
                  <TableCell className="max-w-xs text-sm text-muted-foreground">
                    {r.voidReason ?? "—"}
                  </TableCell>
                  <TableCell className="text-left">
                    {!r.voidedAt && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setDialog({ kind: "void", id: r.id })}
                      >
                        <Undo2 className="size-4" />
                        ألغِ الواقعة
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {dialog && (
        <ReasonDialog
          title={dialog.kind === "lift" ? "رفع الإيقاف" : "إلغاء واقعة"}
          description={
            dialog.kind === "lift"
              ? "ستُلغى كل الوقائع المحتسبة لهذا الراكب ويعود بإمكانه الحجز فوراً."
              : "لن تُحتسب هذه الواقعة بعد الآن. تبقى في السجل مع سببها."
          }
          onClose={() => setDialog(null)}
          onSubmit={(reason) =>
            dialog.kind === "lift"
              ? liftBlockAction(riderId, reason)
              : voidNoShowAction(dialog.id, reason)
          }
        />
      )}
    </section>
  );
}

/**
 * A reason is required to submit — the field is the point of the dialog, not a
 * formality attached to a confirm button.
 */
function ReasonDialog({
  title,
  description,
  onClose,
  onSubmit,
}: {
  title: string;
  description: string;
  onClose: () => void;
  onSubmit: (reason: string) => Promise<{ ok: true } | { ok: false; message: string }>;
}) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  const submit = () => {
    startTransition(async () => {
      const result = await onSubmit(reason);
      if (result.ok) {
        onClose();
        router.refresh();
      } else {
        setError(result.message);
      }
    });
  };

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <Label htmlFor="reason">السبب (مطلوب)</Label>
          <Input
            id="reason"
            value={reason}
            onChange={(e) => {
              setReason(e.target.value);
              setError(null);
            }}
            placeholder="مثال: ظرف طارئ — مراجعة مستشفى"
            aria-invalid={error ? true : undefined}
          />
          {error && (
            <p role="alert" className="flex items-center gap-1.5 text-sm text-destructive">
              <TriangleAlert className="size-4" />
              {error}
            </p>
          )}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={pending}>
            تراجع
          </Button>
          <Button onClick={submit} disabled={pending || reason.trim().length < 3}>
            {pending ? "جارٍ الحفظ…" : "تأكيد"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
