"use client";

import { useRouter } from "next/navigation";

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCount, formatDate } from "@/lib/format";
import { ADMIN_ACTION_AR, ENTITY_TYPE_AR } from "@/lib/labels";
import type { AdminAction } from "@/lib/types";

/** Filter values that map to an entityType, plus "all". */
const ENTITY_TYPES = ["", "BOOKING", "TRIP", "DRIVER", "RIDER"] as const;

export function ActionsClient({
  actions,
  admins,
  selected,
}: {
  actions: AdminAction[];
  admins: { adminId: string; adminUsername: string }[];
  selected: { adminId: string; entityType: string };
}) {
  const router = useRouter();

  const setFilter = (key: "adminId" | "entityType", value: string) => {
    const params = new URLSearchParams();
    const next = { ...selected, [key]: value };
    if (next.adminId) params.set("adminId", next.adminId);
    if (next.entityType) params.set("entityType", next.entityType);
    const query = params.toString();
    router.push(query ? `/actions?${query}` : "/actions");
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">سجل الإجراءات</h1>
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
          كل تدخّل إداري: مَن نفّذه، وعلى أي شيء، ولماذا. السجل لا يُعدَّل ولا
          يُحذف منه.
        </p>
      </div>

      <div className="flex flex-wrap gap-3">
        <label className="flex items-center gap-2 text-sm">
          <span className="text-muted-foreground">الأدمن</span>
          <select
            className="rounded-lg border border-border bg-background px-3 py-1.5 text-sm"
            value={selected.adminId}
            onChange={(e) => setFilter("adminId", e.target.value)}
            aria-label="تصفية حسب الأدمن"
          >
            <option value="">الكل</option>
            {admins.map((a) => (
              <option key={a.adminId} value={a.adminId}>
                {a.adminUsername}
              </option>
            ))}
          </select>
        </label>

        <label className="flex items-center gap-2 text-sm">
          <span className="text-muted-foreground">النوع</span>
          <select
            className="rounded-lg border border-border bg-background px-3 py-1.5 text-sm"
            value={selected.entityType}
            onChange={(e) => setFilter("entityType", e.target.value)}
            aria-label="تصفية حسب نوع الكيان"
          >
            {ENTITY_TYPES.map((t) => (
              <option key={t || "all"} value={t}>
                {t ? (ENTITY_TYPE_AR[t] ?? t) : "الكل"}
              </option>
            ))}
          </select>
        </label>
      </div>

      <h2 className="text-lg font-semibold">
        الإجراءات{actions.length > 0 ? ` (${formatCount(actions.length)})` : ""}
      </h2>

      {actions.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border py-12 text-center text-sm text-muted-foreground">
          لا توجد إجراءات مطابقة.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>الوقت</TableHead>
                <TableHead>الأدمن</TableHead>
                <TableHead>الإجراء</TableHead>
                <TableHead>الكيان</TableHead>
                <TableHead>السبب</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {actions.map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="tabular-nums whitespace-nowrap">
                    {formatDate(a.createdAt)}
                  </TableCell>
                  {/* The username was COPIED into the row at write time, so it
                      still reads correctly after the account is removed —
                      which is exactly when an incident gets reviewed. */}
                  <TableCell className="font-medium">{a.adminUsername}</TableCell>
                  <TableCell>{ADMIN_ACTION_AR[a.type] ?? a.type}</TableCell>
                  <TableCell>
                    <a
                      className="underline underline-offset-4"
                      href={entityHref(a)}
                    >
                      {ENTITY_TYPE_AR[a.entityType] ?? a.entityType}
                    </a>
                  </TableCell>
                  <TableCell className="max-w-sm text-sm text-muted-foreground">
                    {a.reason}
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

/**
 * Link straight to the thing that was acted on.
 *
 * A BOOKING id cannot be opened directly — the support search resolves it to
 * its trip, which is the view that actually shows the booking in context.
 */
function entityHref(a: AdminAction): string {
  switch (a.entityType) {
    case "TRIP":
      return `/support?trip=${a.entityId}`;
    case "DRIVER":
      return `/support?driver=${a.entityId}`;
    case "RIDER":
      return `/support?rider=${a.entityId}`;
    default:
      return `/support?q=${a.entityId}`;
  }
}
