"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Route, IdCard, ShieldCheck } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { cn } from "@/lib/utils";

interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  superAdminOnly?: boolean;
}

const ITEMS: NavItem[] = [
  { href: "/dashboard", label: "لوحة المعلومات", icon: LayoutDashboard },
  { href: "/corridors", label: "الممرات والتسعير", icon: Route },
  { href: "/drivers", label: "السائقون", icon: IdCard },
  { href: "/admins", label: "إدارة المدراء", icon: ShieldCheck, superAdminOnly: true },
];

/**
 * Sidebar navigation. A client component only because it highlights the active
 * route from `usePathname()`.
 *
 * `isSuperAdmin` comes from the server layout, which read it from
 * `/admin/auth/me` — never from a JWT decoded in the browser.
 */
export function PanelNav({ isSuperAdmin }: { isSuperAdmin: boolean }) {
  const pathname = usePathname();
  const items = ITEMS.filter((item) => !item.superAdminOnly || isSuperAdmin);

  return (
    <nav className="flex-1 space-y-1 px-3">
      {items.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
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
          </Link>
        );
      })}
    </nav>
  );
}
