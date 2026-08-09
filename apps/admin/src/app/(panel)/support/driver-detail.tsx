"use client";

import { useState } from "react";
import { Ban, CircleCheck } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cityAr } from "@/lib/cities";
import { formatCount, formatDate, formatPrice, formatRating } from "@/lib/format";
import { DOC_STATUS_AR, DOC_TYPE_AR, DRIVER_STATUS_AR, TRIP_STATUS_AR } from "@/lib/labels";
import type { DriverSupportView } from "@/lib/types";
import { ReasonDialog } from "./reason-dialog";
import { suspendDriverAction, unsuspendDriverAction } from "./actions";

export function DriverDetail({ view }: { view: DriverSupportView }) {
  const [dialog, setDialog] = useState<"suspend" | "unsuspend" | null>(null);
  const { profile, trips, earnings, ratingsReceived } = view;

  return (
    <section className="space-y-6">
      <div className="rounded-xl border border-border p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">{profile.user.name ?? "بدون اسم"}</h2>
            <p dir="ltr" className="text-start text-sm tabular-nums text-muted-foreground">
              {profile.user.phone}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              انضم في {formatDate(profile.user.createdAt)}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant={profile.status === "APPROVED" ? "default" : "secondary"}>
              {DRIVER_STATUS_AR[profile.status] ?? profile.status}
            </Badge>
            {profile.status === "APPROVED" && (
              <Button variant="outline" size="sm" onClick={() => setDialog("suspend")}>
                <Ban className="size-4" />
                أوقف السائق
              </Button>
            )}
            {profile.status === "SUSPENDED" && (
              <Button variant="outline" size="sm" onClick={() => setDialog("unsuspend")}>
                <CircleCheck className="size-4" />
                ارفع الإيقاف
              </Button>
            )}
          </div>
        </div>
        {profile.rejectionReason && (
          <p className="mt-3 text-sm text-muted-foreground">
            سبب الرفض: {profile.rejectionReason}
          </p>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat label="التقييم" value={formatRating(profile.ratingAvg)} />
        <Stat label="رحلات مكتملة" value={formatCount(profile.tripsDone)} />
        <Stat label="إجمالي النقد" value={formatPrice(earnings.total)} />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-border p-4">
          <h3 className="text-sm font-semibold">المركبة</h3>
          {profile.vehicle ? (
            <div className="mt-2 space-y-1 text-sm">
              <p>
                {profile.vehicle.make} {profile.vehicle.model} — {profile.vehicle.color}
              </p>
              {/* The plate is an identifier matched against a metal plate:
                  Western digits, forced LTR (CLAUDE.md). */}
              <p dir="ltr" className="text-start tabular-nums text-muted-foreground">
                {profile.vehicle.plate}
              </p>
              <p className="text-muted-foreground">
                السعة {formatCount(profile.vehicle.seats)}
              </p>
            </div>
          ) : (
            <p className="mt-2 text-sm text-muted-foreground">لا توجد مركبة مسجّلة.</p>
          )}
        </div>

        <div className="rounded-xl border border-border p-4">
          <h3 className="text-sm font-semibold">الوثائق</h3>
          {profile.documents.length === 0 ? (
            <p className="mt-2 text-sm text-muted-foreground">لا توجد وثائق.</p>
          ) : (
            <ul className="mt-2 space-y-1 text-sm">
              {profile.documents.map((d) => (
                <li key={d.id} className="flex items-center justify-between gap-2">
                  <span>{DOC_TYPE_AR[d.type] ?? d.type}</span>
                  <Badge variant={d.status === "APPROVED" ? "default" : "secondary"}>
                    {DOC_STATUS_AR[d.status] ?? d.status}
                  </Badge>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      <div className="space-y-3">
        <h3 className="text-base font-semibold">
          الرحلات{trips.length > 0 ? ` (${formatCount(trips.length)})` : ""}
        </h3>
        {trips.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border py-10 text-center text-sm text-muted-foreground">
            لم يعلن هذا السائق أي رحلة.
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>المسار</TableHead>
                  <TableHead>الموعد</TableHead>
                  <TableHead>الحالة</TableHead>
                  <TableHead>المقاعد</TableHead>
                  <TableHead>السعر</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {trips.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell>
                      <a className="underline underline-offset-4" href={`/support?trip=${t.id}`}>
                        {cityAr(t.originCity)} إلى {cityAr(t.destCity)}
                      </a>
                    </TableCell>
                    <TableCell className="tabular-nums">{formatDate(t.departureTime)}</TableCell>
                    <TableCell>{TRIP_STATUS_AR[t.status] ?? t.status}</TableCell>
                    {/* Two digit runs either side of the dash — one directional
                        run, so no dot-like glyph can land beside a numeral. */}
                    <TableCell className="tabular-nums">
                      {formatCount(t.seatsTotal - t.seatsAvailable)} من{" "}
                      {formatCount(t.seatsTotal)}
                    </TableCell>
                    <TableCell className="tabular-nums">{formatPrice(t.pricePerSeat)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </div>

      <div className="rounded-xl border border-border p-4">
        <h3 className="text-sm font-semibold">تقييمات استلمها</h3>
        {ratingsReceived.length === 0 ? (
          <p className="mt-2 text-sm text-muted-foreground">لا توجد تقييمات.</p>
        ) : (
          <ul className="mt-2 space-y-1 text-sm">
            {ratingsReceived.map((r) => (
              <li key={r.id} className="flex items-center justify-between gap-2">
                <span className="tabular-nums">{formatCount(r.score)} من ٥</span>
                <span className="text-xs text-muted-foreground">{formatDate(r.createdAt)}</span>
              </li>
            ))}
          </ul>
        )}
      </div>

      {dialog === "suspend" && (
        <ReasonDialog
          title="إيقاف سائق"
          description="لن يقدر على إعلان رحلات جديدة. رحلاته القائمة لا تتأثر."
          confirmLabel="أوقف"
          destructive
          onClose={() => setDialog(null)}
          onSubmit={(reason) => suspendDriverAction(profile.id, reason)}
        />
      )}
      {dialog === "unsuspend" && (
        <ReasonDialog
          title="رفع إيقاف سائق"
          description="سيعود الحساب معتمداً ويقدر على إعلان الرحلات."
          onClose={() => setDialog(null)}
          onSubmit={(reason) => unsuspendDriverAction(profile.id, reason)}
        />
      )}
    </section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border p-4">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
    </div>
  );
}


