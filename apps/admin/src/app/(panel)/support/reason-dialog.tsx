"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { TriangleAlert } from "lucide-react";

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
import type { ActionResult } from "./actions";

/**
 * The one dialog every intervention goes through.
 *
 * ## Why a reason is mandatory, everywhere, with no exception
 *
 * These actions cancel someone's journey or stop a driver earning. They get
 * reviewed weeks later, by which time nobody remembers the phone call that
 * prompted them. The sentence typed here is the only thing that will still
 * exist — so the confirm button stays disabled until it is written.
 *
 * It is deliberately ONE component rather than a reason field bolted onto each
 * action: a second copy is how one of them ends up with an optional reason.
 */
export function ReasonDialog({
  title,
  description,
  confirmLabel = "تأكيد",
  destructive = false,
  onClose,
  onSubmit,
}: {
  title: string;
  description: string;
  confirmLabel?: string;
  destructive?: boolean;
  onClose: () => void;
  onSubmit: (reason: string) => Promise<ActionResult>;
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
          <Label htmlFor="intervene-reason">السبب (مطلوب)</Label>
          <Input
            id="intervene-reason"
            value={reason}
            onChange={(e) => {
              setReason(e.target.value);
              setError(null);
            }}
            placeholder="مثال: اتصل الراكب — حجز بالخطأ"
            aria-invalid={error ? true : undefined}
          />
          <p className="text-xs text-muted-foreground">
            يُسجَّل السبب باسمك في سجل الإجراءات.
          </p>
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
          <Button
            variant={destructive ? "destructive" : "default"}
            onClick={submit}
            disabled={pending || reason.trim().length < 3}
          >
            {pending ? "جارٍ التنفيذ…" : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
