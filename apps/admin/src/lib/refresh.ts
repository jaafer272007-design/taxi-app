/**
 * How often each auto-refreshing panel view re-asks the server.
 *
 * The panel is a set of React Server Components, so "refreshing" is
 * `router.refresh()` — the RSC payload is re-fetched and re-rendered without
 * losing scroll position, dialog state or the row a filter is on. There is no
 * client-side data layer to keep in sync, which is exactly why this is the
 * right shape here and a poll of a JSON endpoint would not be.
 *
 * Not every view polls, and that is deliberate:
 *
 *  * **Drivers** — the one that matters. A driver stuck at «بانتظار المراجعة»
 *    cannot post a single trip until an admin sees them, and an admin sitting
 *    on this page with a stale list has no way to know someone is waiting.
 *  * **Dashboard** — counts, watched over a shift rather than acted on in the
 *    second, so a slower beat is plenty.
 *  * **Corridors — deliberately NOT polled.** 306 rows that only ever change
 *    when an admin changes them, and the admin who changed them is already
 *    looking at the result of their own action.
 */

/** 20s — a driver waiting to be approved is blocked the whole time. */
export const DRIVERS_REFRESH_MS = 20_000;

/** 60s — headline counts, not an operational queue. */
export const DASHBOARD_REFRESH_MS = 60_000;

/**
 * `?refreshMs=` — an opt-in override of the beat for the tab you are in.
 *
 * Two reasons it exists rather than a build-time flag. Asserting "the beat
 * stopped while the tab was hidden" against a 20-second interval means a
 * 60-second test; and a build-time flag would shorten the beat for the WHOLE
 * E2E suite, so every other spec would have `router.refresh()` firing
 * underneath its clicks. A search param is opted into by one spec and changes
 * nothing anywhere else.
 *
 * Floored at {@link MIN_REFRESH_MS}: the worst anyone can do with it is make
 * their own tab refresh once a second.
 */
export const REFRESH_PARAM = "refreshMs";

/** No caller may ask for a faster beat than this. */
export const MIN_REFRESH_MS = 1_000;

export function refreshOverrideFrom(search: string): number | null {
  const raw = new URLSearchParams(search).get(REFRESH_PARAM);
  if (raw === null) return null;
  const ms = Number(raw);
  return Number.isFinite(ms) && ms >= MIN_REFRESH_MS ? ms : null;
}
