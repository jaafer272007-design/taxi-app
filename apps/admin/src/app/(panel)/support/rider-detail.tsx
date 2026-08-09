"use client";

import { useState } from "react";
import { ShieldOff, Undo2, XCircle } from "lucide-react";

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
import { BOOKING_STATUS_AR, TRIP_STATUS_AR } from "@/lib/labels";
import type { RiderSupportView } from "@/lib/types";
import { ReasonDialog } from "./reason-dialog";
import { cancelBookingAction, liftBlockAction, voidNoShowAction } from "./actions";

/** A booking is only cancellable while its TRIP has not started — the same
 *  rule the rider's own app follows, and the same one the server enforces.
 *  Offering an action the server will refuse is worse than offering none. */
const CANCELLABLE_TRIP = ["OPEN", "LOCKED"];

type Dialog =
  | { kind: "cancel-booking"; id: string }
  | { kind: "void-no-show"; id: string }
  | { kind: "lift-block" }
  | null;

export function RiderDetail({ view }: { view: RiderSupportView }) {
  const [dialog, setDialog] = useState<Dialog>(null);
  const { user, bookings, noShows, block, ratingsGiven, ratingsReceived } = view;

  return (
    <section className="space-y-6">
      <div className="rounded-xl border border-border p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">{user.name ?? "بدون اسم"}</h2>
            {/* Privileged view: an admin needs the number to match a caller to
                an account. It is never exposed outside this session. */}
            <p dir="ltr" className="text-start text-sm tabular-nums text-muted-foreground">
              {user.phone}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              {user.gender === "FEMALE" ? "أنثى" : user.gender === "MALE" ? "ذكر" : "غير محدد"}
              {" — انضم في "}
              {formatDate(user.createdAt)}
            </p>
          </div>
          <div className="flex items-center gap-2">
            {block.blocked ? (
              <Badge variant="destructive">
                موقوف حتى {block.blockedUntil ? formatDate(block.blockedUntil) : "—"}
              </Badge>
            ) : (
              <Badge variant="secondary">غير موقوف</Badge>
            )}
            {noShows.some((r) => !r.voidedAt) && (
              <Button variant="outline" size="sm" onClick={() => setDialog({ kind: "lift-block" })}>
                <ShieldOff className="size-4" />
                ارفع الإيقاف
              </Button>
            )}
          </div>
        </div>
      </div>

      <div className="space-y-3">
        <h3 className="text-base font-semibold">
          الحجوزات{bookings.length > 0 ? ` (${formatCount(bookings.length)})` : ""}
        </h3>
        {bookings.length === 0 ? (
          <Empty>لا توجد حجوزات.</Empty>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الرحلة</TableHead>
                  <TableHead>الموعد</TableHead>
                  <TableHead>المقاعد</TableHead>
                  <TableHead>الأجرة</TableHead>
                  <TableHead>حالة الحجز</TableHead>
                  <TableHead>حالة الرحلة</TableHead>
                  <TableHead className="text-left">إجراء</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {bookings.map((b) => (
                  <TableRow key={b.id}>
                    <TableCell>
                      <a className="underline underline-offset-4" href={`/support?trip=${b.tripId}`}>
                        {cityAr(b.trip.originCity)} إلى {cityAr(b.trip.destCity)}
                      </a>
                    </TableCell>
                    <TableCell className="tabular-nums">
                      {formatDate(b.trip.departureTime)}
                    </TableCell>
                    <TableCell className="tabular-nums">{formatSeats(b.seatCount)}</TableCell>
                    <TableCell className="tabular-nums">{formatPrice(b.fare)}</TableCell>
                    <TableCell>
                      <Badge variant={b.status === "CANCELLED" ? "secondary" : "default"}>
                        {BOOKING_STATUS_AR[b.status] ?? b.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {TRIP_STATUS_AR[b.trip.status] ?? b.trip.status}
                    </TableCell>
                    <TableCell className="text-left">
                      {b.status === "CONFIRMED" && CANCELLABLE_TRIP.includes(b.trip.status) && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setDialog({ kind: "cancel-booking", id: b.id })}
                        >
                          <XCircle className="size-4" />
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

      <div className="space-y-3">
        <h3 className="text-base font-semibold">سجل عدم الحضور</h3>
        {noShows.length === 0 ? (
          <Empty>لا توجد وقائع.</Empty>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>التاريخ</TableHead>
                  <TableHead>الحالة</TableHead>
                  <TableHead>سبب الإلغاء</TableHead>
                  <TableHead className="text-left">إجراء</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {noShows.map((r) => (
                  <TableRow key={r.id} className={r.voidedAt ? "opacity-60" : undefined}>
                    <TableCell className="tabular-nums">{formatDate(r.createdAt)}</TableCell>
                    <TableCell>
                      <Badge variant={r.voidedAt ? "secondary" : "destructive"}>
                        {r.voidedAt ? "ملغاة" : "محتسبة"}
                      </Badge>
                    </TableCell>
                    <TableCell className="max-w-xs text-sm text-muted-foreground">
                      {r.voidReason ?? "—"}
                    </TableCell>
                    <TableCell className="text-left">
                      {!r.voidedAt && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setDialog({ kind: "void-no-show", id: r.id })}
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
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <RatingsCard title="تقييمات أعطاها" ratings={ratingsGiven} />
        <RatingsCard title="تقييمات استلمها" ratings={ratingsReceived} />
      </div>

      {dialog?.kind === "cancel-booking" && (
        <ReasonDialog
          title="إلغاء حجز نيابةً عن الراكب"
          description="سيُعاد المقعد للرحلة ويُشعَر السائق والراكب — بنفس المسار الذي يستعمله الراكب."
          confirmLabel="ألغِ الحجز"
          destructive
          onClose={() => setDialog(null)}
          onSubmit={(reason) => cancelBookingAction(dialog.id, reason)}
        />
      )}
      {dialog?.kind === "void-no-show" && (
        <ReasonDialog
          title="إلغاء واقعة عدم حضور"
          description="لن تُحتسب هذه الواقعة بعد الآن. تبقى في السجل مع سببها."
          onClose={() => setDialog(null)}
          onSubmit={(reason) => voidNoShowAction(dialog.id, reason)}
        />
      )}
      {dialog?.kind === "lift-block" && (
        <ReasonDialog
          title="رفع الإيقاف"
          description="ستُلغى كل الوقائع المحتسبة ويعود بإمكان الراكب الحجز فوراً."
          onClose={() => setDialog(null)}
          onSubmit={(reason) => liftBlockAction(user.id, reason)}
        />
      )}
    </section>
  );
}

function RatingsCard({
  title,
  ratings,
}: {
  title: string;
  ratings: RiderSupportView["ratingsGiven"];
}) {
  return (
    <div className="rounded-xl border border-border p-4">
      <h3 className="text-sm font-semibold">{title}</h3>
      {ratings.length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">لا توجد تقييمات.</p>
      ) : (
        <ul className="mt-2 space-y-1 text-sm">
          {ratings.map((r) => (
            <li key={r.id} className="flex items-center justify-between gap-2">
              <span className="tabular-nums">{formatCount(r.score)} من ٥</span>
              <span className="text-xs text-muted-foreground">{formatDate(r.createdAt)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Empty({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-border py-10 text-center text-sm text-muted-foreground">
      {children}
    </div>
  );
}


