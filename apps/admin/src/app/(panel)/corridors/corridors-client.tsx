"use client";

import { useState, useTransition } from "react";
import { Plus, Pencil, Route } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "@/components/ui/table";
import { cityAr } from "@/lib/cities";
import { formatIqd, formatPrice } from "@/lib/format";
import type { Corridor } from "@/lib/types";
import { CorridorFormDialog } from "./corridor-form-dialog";
import { toggleCorridorActiveAction } from "./actions";

export function CorridorsClient({ corridors }: { corridors: Corridor[] }) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<Corridor | undefined>(undefined);
  const [, startTransition] = useTransition();
  // Tracks in-flight toggles so a slow network doesn't let a second tap race.
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());

  function openCreate() {
    setEditing(undefined);
    setDialogOpen(true);
  }

  function openEdit(corridor: Corridor) {
    setEditing(corridor);
    setDialogOpen(true);
  }

  function onToggle(corridor: Corridor, next: boolean) {
    setPendingIds((prev) => new Set(prev).add(corridor.id));
    startTransition(async () => {
      const result = await toggleCorridorActiveAction(corridor.id, next);
      setPendingIds((prev) => {
        const copy = new Set(prev);
        copy.delete(corridor.id);
        return copy;
      });
      if (!result.ok) {
        toast.error(result.message);
        return;
      }
      toast.success(next ? "تم تفعيل الممر" : "تم تعطيل الممر");
    });
  }

  return (
    <div className="grid gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">الممرات والتسعير</h1>
          <p className="text-sm text-muted-foreground">
            كل ممر يحدّد مساراً قابلاً للبحث والنشر. السائق يحدد سعر المقعد ضمن
            المدى المسموح، والمقترح هو ما يُملأ له مسبقاً.
          </p>
        </div>
        <Button onClick={openCreate}>
          <Plus className="size-4" />
          أنشئ ممراً جديداً
        </Button>
      </div>

      {corridors.length === 0 ? (
        <div className="flex flex-col items-center gap-4 rounded-xl border border-dashed border-border py-16 text-center">
          <div className="flex size-14 items-center justify-center rounded-full bg-muted text-muted-foreground">
            <Route className="size-6" />
          </div>
          <div className="space-y-1">
            <p className="font-medium">لا توجد ممرات بعد</p>
            <p className="text-sm text-muted-foreground">
              أنشئ أول ممر لجعل مساره قابلاً للبحث والنشر.
            </p>
          </div>
          <Button onClick={openCreate}>
            <Plus className="size-4" />
            أنشئ ممراً جديداً
          </Button>
        </div>
      ) : (
        <div className="rounded-xl border border-border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>من</TableHead>
                <TableHead>إلى</TableHead>
                <TableHead>السعر المقترح</TableHead>
                <TableHead>المدى المسموح</TableHead>
                <TableHead>الحالة</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {corridors.map((corridor) => (
                <TableRow key={corridor.id}>
                  <TableCell className="font-medium">
                    {cityAr(corridor.originCity)}
                  </TableCell>
                  <TableCell className="font-medium">
                    {cityAr(corridor.destCity)}
                  </TableCell>
                  <TableCell className="tabular-nums-ar" dir="ltr">
                    {formatPrice(corridor.suggestedPricePerSeat)}
                  </TableCell>
                  <TableCell
                    className="tabular-nums-ar whitespace-nowrap text-muted-foreground"
                    dir="ltr"
                  >
                    {corridor.minPricePerSeat === corridor.maxPricePerSeat
                      ? "ثابت"
                      : `${formatIqd(corridor.minPricePerSeat)} – ${formatPrice(
                          corridor.maxPricePerSeat,
                        )}`}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Switch
                        checked={corridor.active}
                        disabled={pendingIds.has(corridor.id)}
                        onCheckedChange={(v) => onToggle(corridor, v)}
                        aria-label={corridor.active ? "تعطيل الممر" : "تفعيل الممر"}
                      />
                      <Badge variant={corridor.active ? "success" : "secondary"}>
                        {corridor.active ? "نشط" : "غير نشط"}
                      </Badge>
                    </div>
                  </TableCell>
                  <TableCell>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => openEdit(corridor)}
                      aria-label="تعديل الممر"
                    >
                      <Pencil className="size-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <CorridorFormDialog open={dialogOpen} onOpenChange={setDialogOpen} corridor={editing} />
    </div>
  );
}
