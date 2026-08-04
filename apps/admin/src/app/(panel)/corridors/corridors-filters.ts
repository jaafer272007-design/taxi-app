import { cityAr } from "@/lib/cities";
import type { Corridor } from "@/lib/types";

export type ActiveFilter = "all" | "active" | "inactive";

export interface CorridorFilters {
  /** Free text; matched against BOTH endpoints, Arabic name or stored key. */
  query: string;
  originCity: string; // "" = any
  destCity: string; // "" = any
  active: ActiveFilter;
}

export const EMPTY_FILTERS: CorridorFilters = {
  query: "",
  originCity: "",
  destCity: "",
  active: "all",
};

export const PAGE_SIZE = 25;

/**
 * Whether any filter is doing something — drives the "clear" affordance and the
 * wording of the empty state ("no match" vs "no corridors at all").
 */
export function hasActiveFilters(f: CorridorFilters): boolean {
  return (
    f.query.trim() !== "" || f.originCity !== "" || f.destCity !== "" || f.active !== "all"
  );
}

/**
 * Apply the filters. Search matches the ARABIC display name as well as the
 * stored key, because the admin reads "النجف" on screen and would reasonably
 * type that — matching only the English key would make search look broken.
 */
export function filterCorridors(
  corridors: readonly Corridor[],
  f: CorridorFilters,
): Corridor[] {
  const q = f.query.trim().toLowerCase();
  return corridors.filter((c) => {
    if (f.originCity && c.originCity !== f.originCity) return false;
    if (f.destCity && c.destCity !== f.destCity) return false;
    if (f.active === "active" && !c.active) return false;
    if (f.active === "inactive" && c.active) return false;
    if (!q) return true;

    const haystack = [
      c.originCity,
      c.destCity,
      cityAr(c.originCity),
      cityAr(c.destCity),
    ]
      .join(" ")
      .toLowerCase();
    return haystack.includes(q);
  });
}

/**
 * Clamp a 1-based page against the current result count.
 *
 * Filtering while on a later page is the classic way to strand someone on a
 * blank screen — deriving the page instead of storing it blindly makes that
 * unrepresentable.
 */
export function clampPage(page: number, totalItems: number): number {
  const pages = Math.max(1, Math.ceil(totalItems / PAGE_SIZE));
  return Math.min(Math.max(1, page), pages);
}

export function pageCount(totalItems: number): number {
  return Math.max(1, Math.ceil(totalItems / PAGE_SIZE));
}

export function pageSlice<T>(items: readonly T[], page: number): T[] {
  const start = (clampPage(page, items.length) - 1) * PAGE_SIZE;
  return items.slice(start, start + PAGE_SIZE);
}
