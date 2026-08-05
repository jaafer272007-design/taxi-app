"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Route, IdCard, ShieldCheck } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { formatCount } from "@/lib/format";
import { cn } from "@/lib/utils";

interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  superAdminOnly?: boolean;
  /** Renders the pending-drivers count when there is one. */
  badge?: "pendingDrivers";
}

const ITEMS: NavItem[] = [
  { href: "/dashboard", label: "لوحة المعلومات", icon: LayoutDashboard },
  { href: "/corridors", label: "الممرات والتسعير", icon: Route },
  { href: "/drivers", label: "السائقون", icon: IdCard, badge: "pendingDrivers" },
  { href: "/admins", label: "إدارة المدراء", icon: ShieldCheck, superAdminOnly: true },
];

/**
 * Sidebar navigation. A client component only because it highlights the active
 * route from `usePathname()`.
 *
 * `isSuperAdmin` comes from the server layout, which read it from
 * `/admin/auth/me` — never from a JWT decoded in the browser. So does
 * [pendingDrivers]: it is a count from the backend's own dashboard aggregate,
 * re-read every time the layout renders, which includes every auto-refresh of
 * the page currently open.
 *
 * That is the one caveat worth knowing: the badge is as fresh as the view the
 * admin is looking at. On /drivers and /dashboard it follows their beat; on
 * /corridors, which is deliberately not polled (306 rows that only change when
 * an admin changes them), it is as of page load.
 */
export function PanelNav({
  isSuperAdmin,
  pendingDrivers = 0,
}: {
  isSuperAdmin: boolean;
  pendingDrivers?: number;
}) {
  const pathname = usePathname();
  const items = ITEMS.filter((item) => !item.superAdminOnly || isSuperAdmin);

  return (
    <nav className="flex-1 space-y-1 px-3">
      {items.map(({ href, label, icon: Icon, badge }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        const count = badge === "pendingDrivers" ? pendingDrivers : 0;
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors",
              active
                ? "bg-sidebar-accent font-semibold text-sidebar-accent-foreground"
                : "text-muted-foreground hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground",
            )}
          >
            <Icon className="size-4 shrink-0" />
            {label}
            {count > 0 && (
              <span
                data-testid="pending-drivers-badge"
                // Warning, not destructive: a queue of applications is work
                // waiting, not something that has gone wrong. Opaque tonal
                // fill — never an alpha wash over the sidebar.
                className="ms-auto min-w-6 rounded-full bg-warning-tonal px-2 py-0.5 text-center text-xs font-bold tabular-nums text-warning"
              >
                {/* The count alone in a pill; a screen reader would otherwise
                    read "السائقون ٣" as if that were the name. */}
                <span className="sr-only">بانتظار المراجعة: </span>
                {formatCount(count)}
              </span>
            )}
          </Link>
        );
      })}
    </nav>
  );
}
