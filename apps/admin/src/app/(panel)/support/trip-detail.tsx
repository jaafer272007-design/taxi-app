"use client";

import { useState } from "react";
import { XCircle } from "lucide-react";

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
import { formatCount, formatDate, formatPrice, formatSeats } from "@/lib/format";
import { ADMIN_ACTION_AR, BOOKING_STATUS_AR, TRIP_STATUS_AR } from "@/lib/labels";
import type { TripSupportView } from "@/lib/types";
import { ReasonDialog } from "./reason-dialog";
import { cancelBookingAction, cancelTripAction } from "./actions";

/** Same window the driver's own cancel has, and the server's. */
const CANCELLABLE = ["OPEN", "LOCKED"];

type Dialog = { kind: "cancel-trip" } | { kind: "cancel-booking"; id: string } | null;

export function TripDetail({ view }: { view: TripSupportView }) {
  const [dialog, setDialog] = useState<Dialog>(null);
  const { trip, driver, vehicle, bookings, adminActions } = view;
  const canCancel = CANCELLABLE.includes(trip.status);

  return (
    <section className="space-y-6">
      <div className="rounded-xl border border-border p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">
              {cityAr(trip.originCity)} إلى {cityAr(trip.destCity)}
            </h2>
            <p className="mt-1 text-sm text-muted-foreground tabular-nums">
              {formatDate(trip.departureTime)}
              {trip.departNow ? " — انطلاق فوري" : ""}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant={trip.status === "CANCELLED" ? "secondary" : "default"}>
              {TRIP_STATUS_AR[trip.status] ?? trip.status}
            </Badge>
            {canCancel && (
              <Button variant="outline" size="sm" onClick={() => setDialog({ kind: "cancel-trip" })}>
                <XCircle className="size-4" />
                ألغِ الرحلة
              </Button>
            )}
          </div>
        </div>

        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <Field label="المقاعد">
            {formatCount(trip.seatsTotal - trip.seatsAvailable)} من {formatCount(trip.seatsTotal)}
          </Field>
          <Field label="السعر للمقعد">{formatPrice(trip.pricePerSeat)}</Field>
          <Field label="النوع">
            {trip.tripType === "WOMEN_FAMILY" ? "نسائية/عائلية" : "عامة"}
          </Field>
        </div>
      </div>

      <div className="rounded-xl border border-border p-4">
        <h3 className="text-sm font-semibold">السائق</h3>
        {driver ? (
          <div className="mt-2 space-y-1 text-sm">
            <a
              className="underline underline-offset-4"
              href={`/support?driver=${driver.id}`}
            >
              {driver.user.name ?? "بدون اسم"}
            </a>
            <p dir="ltr" className="text-start tabular-nums text-muted-foreground">
              {driver.user.phone}
            </p>
            {vehicle && (
              <p className="text-muted-foreground">
                {vehicle.make} {vehicle.model} — {vehicle.color}
                {" — "}
                <span dir="ltr" className="tabular-nums">
                  {vehicle.plate}
                </span>
              </p>
            )}
          </div>
        ) : (
          <p className="mt-2 text-sm text-muted-foreground">لم يُعثر على السائق.</p>
        )}
      </div>

      <div className="space-y-3">
        <h3 className="text-base font-semibold">
          الحجوزات{bookings.length > 0 ? ` (${formatCount(bookings.length)})` : ""}
        </h3>
        {bookings.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border py-10 text-center text-sm text-muted-foreground">
            لا توجد حجوزات على هذه الرحلة.
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الراكب</TableHead>
                  <TableHead>الهاتف</TableHead>
                  <TableHead>المقاعد</TableHead>
                  <TableHead>الانطلاق</TableHead>
                  <TableHead>النزول</TableHead>
                  <TableHead>الحالة</TableHead>
                  <TableHead className="text-left">إجراء</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {bookings.map((b) => (
                  <TableRow key={b.id}>
                    <TableCell>
                      {b.rider ? (
                        <a
                          className="underline underline-offset-4"
                          href={`/support?rider=${b.rider.id}`}
                        >
                          {b.rider.name ?? "بدون اسم"}
                        </a>
                      ) : (
                        "—"
                      )}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {b.rider?.phone ?? "—"}
                    </TableCell>
                    <TableCell className="tabular-nums">{formatSeats(b.seatCount)}</TableCell>
                    <TableCell className="max-w-[12rem] truncate">{b.pickupLabel}</TableCell>
                    <TableCell className="max-w-[12rem] truncate">{b.dropoffLabel}</TableCell>
                    <TableCell>
                      <Badge variant={b.status === "CANCELLED" ? "secondary" : "default"}>
                        {BOOKING_STATUS_AR[b.status] ?? b.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-left">
                      {b.status === "CONFIRMED" && canCancel && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setDialog({ kind: "cancel-booking", id: b.id })}
                        >
                          ألغِ الحجز
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </div>

      {/* There is no status-history table in Phase 1. This is the honest
          substitute: what an ADMIN did to this trip is recorded; what the
          state machine did on its own is not. Saying so beats inventing a
          timeline out of timestamps. */}
      <div className="space-y-3">
        <h3 className="text-base font-semibold">إجراءات إدارية على هذه الرحلة</h3>
        {adminActions.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border py-10 text-center text-sm text-muted-foreground">
            لا توجد إجراءات مسجّلة.
          </div>
        ) : (
          <ul className="space-y-2">
            {adminActions.map((a) => (
              <li key={a.id} className="rounded-xl border border-border p-3 text-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium">{ADMIN_ACTION_AR[a.type] ?? a.type}</span>
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {formatDate(a.createdAt)} — {a.adminUsername}
                  </span>
                </div>
                <p className="mt-1 text-muted-foreground">{a.reason}</p>
              </li>
            ))}
          </ul>
        )}
      </div>

      {dialog?.kind === "cancel-trip" && (
        <ReasonDialog
          title="إلغاء الرحلة نيابةً عن السائق"
          description="ستُلغى كل الحجوزات المؤكدة ويُشعَر كل راكب — بنفس المسار الذي يستعمله السائق."
          confirmLabel="ألغِ الرحلة"
          destructive
          onClose={() => setDialog(null)}
          onSubmit={(reason) => cancelTripAction(trip.id, reason)}
        />
      )}
      {dialog?.kind === "cancel-booking" && (
        <ReasonDialog
          title="إلغاء حجز نيابةً عن الراكب"
          description="سيُعاد المقعد للرحلة ويُشعَر السائق والراكب."
          confirmLabel="ألغِ الحجز"
          destructive
          onClose={() => setDialog(null)}
          onSubmit={(reason) => cancelBookingAction(dialog.id, reason)}
        />
      )}
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-sm tabular-nums">{children}</p>
    </div>
  );
}
