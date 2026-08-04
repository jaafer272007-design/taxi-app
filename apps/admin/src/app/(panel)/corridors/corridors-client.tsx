"use client";

import { useMemo, useState, useTransition } from "react";
import { Plus, Pencil, Route, Search, X, ChevronRight, ChevronLeft } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "@/components/ui/table";
import { cityAr, IRAQI_CITIES } from "@/lib/cities";
import { formatCount, formatIqd, formatPrice } from "@/lib/format";
import type { Corridor } from "@/lib/types";
import { CorridorFormDialog } from "./corridor-form-dialog";
import { toggleCorridorActiveAction } from "./actions";
import {
  clampPage,
  EMPTY_FILTERS,
  filterCorridors,
  hasActiveFilters,
  PAGE_SIZE,
  pageCount,
  pageSlice,
  type ActiveFilter,
  type CorridorFilters,
} from "./corridors-filters";

export function CorridorsClient({ corridors }: { corridors: Corridor[] }) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<Corridor | undefined>(undefined);
  const [filters, setFilters] = useState<CorridorFilters>(EMPTY_FILTERS);
  const [rawPage, setRawPage] = useState(1);
  const [, startTransition] = useTransition();
  // Tracks in-flight toggles so a slow network doesn't let a second tap race.
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());

  // The grid is 306 rows — every ordered pair of the 18 governorates. Filtering
  // and paging happen client-side because the whole list already arrived in one
  // payload: a round trip per keystroke would be slower and no more correct.
  const filtered = useMemo(() => filterCorridors(corridors, filters), [corridors, filters]);
  // Derived, not stored: narrowing the filter while on page 8 must not strand
  // the admin on a blank screen.
  const page = clampPage(rawPage, filtered.length);
  const pages = pageCount(filtered.length);
  const visible = pageSlice(filtered, page);
  const filtering = hasActiveFilters(filters);

  function patchFilters(patch: Partial<CorridorFilters>) {
    setFilters((prev) => ({ ...prev, ...patch }));
    setRawPage(1);
  }

  function clearFilters() {
    setFilters(EMPTY_FILTERS);
    setRawPage(1);
  }

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
        <>
          <div className="grid gap-3 rounded-xl border border-border p-3 sm:grid-cols-2 lg:grid-cols-4">
            <div className="relative sm:col-span-2 lg:col-span-1">
              <Search className="pointer-events-none absolute inset-y-0 start-3 my-auto size-4 text-muted-foreground" />
              <Input
                value={filters.query}
                onChange={(e) => patchFilters({ query: e.target.value })}
                placeholder="ابحث بالمدينة…"
                aria-label="ابحث بالمدينة"
                className="ps-9"
              />
            </div>

            <Select
              value={filters.originCity || "ALL"}
              onValueChange={(v) => patchFilters({ originCity: v === "ALL" ? "" : v })}
            >
              <SelectTrigger aria-label="تصفية حسب مدينة الانطلاق">
                <SelectValue placeholder="من: الكل" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">من: الكل</SelectItem>
                {IRAQI_CITIES.map((c) => (
                  <SelectItem key={c.key} value={c.key}>
                    من: {c.ar}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <Select
              value={filters.destCity || "ALL"}
              onValueChange={(v) => patchFilters({ destCity: v === "ALL" ? "" : v })}
            >
              <SelectTrigger aria-label="تصفية حسب مدينة الوصول">
                <SelectValue placeholder="إلى: الكل" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">إلى: الكل</SelectItem>
                {IRAQI_CITIES.map((c) => (
                  <SelectItem key={c.key} value={c.key}>
                    إلى: {c.ar}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <div className="flex gap-2">
              <Select
                value={filters.active}
                onValueChange={(v) => patchFilters({ active: v as ActiveFilter })}
              >
                <SelectTrigger aria-label="تصفية حسب الحالة" className="flex-1">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">الحالة: الكل</SelectItem>
                  <SelectItem value="active">النشطة فقط</SelectItem>
                  <SelectItem value="inactive">المعطّلة فقط</SelectItem>
                </SelectContent>
              </Select>
              {filtering && (
                <Button variant="outline" size="icon" onClick={clearFilters} aria-label="إزالة الفلاتر">
                  <X className="size-4" />
                </Button>
              )}
            </div>
          </div>

          <p className="text-sm text-muted-foreground" aria-live="polite">
            {filtering
              ? `${formatCount(filtered.length)} من ${formatCount(corridors.length)} ممر`
              : `${formatCount(corridors.length)} ممر`}
          </p>

          {filtered.length === 0 ? (
            <div className="flex flex-col items-center gap-4 rounded-xl border border-dashed border-border py-16 text-center">
              <div className="flex size-14 items-center justify-center rounded-full bg-muted text-muted-foreground">
                <Search className="size-6" />
              </div>
              <p className="font-medium">لا ممر يطابق البحث</p>
              <Button variant="outline" onClick={clearFilters}>
                إزالة الفلاتر
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
                  {visible.map((corridor) => (
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

          {pages > 1 && (
            <div className="flex items-center justify-between gap-3">
              {/* The row range, not just the page number: "which of 306 am I
                  looking at" is the question an admin scrolling a long grid
                  actually has. */}
              <p className="text-sm text-muted-foreground tabular-nums-ar">
                {`${formatCount((page - 1) * PAGE_SIZE + 1)}–${formatCount(
                  Math.min(page * PAGE_SIZE, filtered.length),
                )} من ${formatCount(filtered.length)}`}
              </p>
              <div className="flex items-center gap-2">
                {/* RTL: "previous" points right. */}
                <Button
                  variant="outline"
                  size="icon"
                  onClick={() => setRawPage(page - 1)}
                  disabled={page <= 1}
                  aria-label="الصفحة السابقة"
                >
                  <ChevronRight className="size-4" />
                </Button>
                <span className="text-sm tabular-nums-ar">
                  {`${formatCount(page)} / ${formatCount(pages)}`}
                </span>
                <Button
                  variant="outline"
                  size="icon"
                  onClick={() => setRawPage(page + 1)}
                  disabled={page >= pages}
                  aria-label="الصفحة التالية"
                >
                  <ChevronLeft className="size-4" />
                </Button>
              </div>
            </div>
          )}
        </>
      )}

      <CorridorFormDialog open={dialogOpen} onOpenChange={setDialogOpen} corridor={editing} />
    </div>
  );
}
