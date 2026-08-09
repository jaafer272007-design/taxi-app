"use client";

import { useRouter } from "next/navigation";
import { CircleSlash, Route as RouteIcon } from "lucide-react";

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
import { formatCount, formatDate } from "@/lib/format";
import type { RouteRequestsPayload } from "@/lib/types";

export function RouteRequestsClient({
  payload,
  unservedOnly,
}: {
  payload: RouteRequestsPayload;
  unservedOnly: boolean;
}) {
  const router = useRouter();
  const { corridors, policy } = payload;

  const setUnserved = (on: boolean) =>
    router.push(on ? "/route-requests?unserved=1" : "/route-requests");

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex gap-2">
          <Button
            variant={unservedOnly ? "outline" : "default"}
            size="sm"
            onClick={() => setUnserved(false)}
          >
            كل الطلبات
          </Button>
          <Button
            variant={unservedOnly ? "default" : "outline"}
            size="sm"
            onClick={() => setUnserved(true)}
          >
            <CircleSlash className="size-4" />
            طلب بلا عرض
          </Button>
        </div>
        {/* The window is stated, not implied: a count that silently drops rows
            after N days is a number nobody can check. */}
        <p className="text-xs text-muted-foreground">
          تُحتسب الطلبات غير المحقّقة خلال آخر {formatCount(policy.ttlDays)} يوماً.
        </p>
      </div>

      {corridors.length === 0 ? (
        <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
          <div className="flex size-14 items-center justify-center rounded-full bg-muted text-muted-foreground">
            <RouteIcon className="size-6" />
          </div>
          <p className="font-medium">
            {unservedOnly ? "لا يوجد ممرّ عليه طلب بلا عرض." : "لا توجد طلبات مسارات بعد."}
          </p>
          <p className="max-w-md text-sm text-muted-foreground">
            {unservedOnly
              ? "كل ممرّ مطلوب عليه رحلة حيّة الآن."
              : "تظهر هنا المسارات التي بحث عنها ركّاب ولم يجدوا رحلات، وضغطوا «أبلغنا أنك تريد هذا المسار»."}
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>المسار</TableHead>
                <TableHead>الطلبات</TableHead>
                <TableHead>الركّاب</TableHead>
                <TableHead>آخر طلب</TableHead>
                <TableHead>العرض الحالي</TableHead>
                <TableHead>الممر</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {corridors.map((row) => (
                <TableRow key={row.corridorId}>
                  <TableCell className="font-medium">
                    {/* Joined with the WORD «إلى» — never an arrow, and never a
                        dot-like separator, which fuses onto an Arabic-Indic
                        digit in this very table. */}
                    {cityAr(row.originCity)} إلى {cityAr(row.destCity)}
                  </TableCell>
                  <TableCell className="tabular-nums font-semibold">
                    {formatCount(row.requestCount)}
                  </TableCell>
                  <TableCell className="tabular-nums text-muted-foreground">
                    {/* Requests vs riders: five taps from one determined person
                        is not the same signal as five people, and only this
                        column tells them apart. */}
                    {formatCount(row.riderCount)}
                  </TableCell>
                  <TableCell className="tabular-nums text-sm text-muted-foreground">
                    {formatDate(row.lastRequestedAt)}
                  </TableCell>
                  <TableCell>
                    {row.activeTrips === 0 ? (
                      // `default` (the brand tone), NOT `destructive`.
                      //
                      // On this screen "no supply" is the row the admin came to
                      // find, and most rows will say it. A page of red badges
                      // reads as a list of failures and stops carrying signal
                      // at all — while what this actually marks is where the
                      // next driver should be recruited.
                      <Badge>بلا رحلات</Badge>
                    ) : (
                      <span className="tabular-nums text-sm text-muted-foreground">
                        {formatCount(row.activeTrips)} رحلة حيّة
                      </span>
                    )}
                  </TableCell>
                  <TableCell>
                    {row.corridorActive ? (
                      <span className="text-sm text-muted-foreground">مفعّل</span>
                    ) : (
                      // A request on a corridor an admin switched off is
                      // information, not an error — it may have been disabled
                      // before the demand showed up.
                      <Badge variant="secondary">معطّل</Badge>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
