"use client";

import { RefreshCw } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { formatClock } from "@/lib/format";
import { refreshOverrideFrom } from "@/lib/refresh";
import { cn } from "@/lib/utils";

/**
 * Auto-refresh for one panel view, plus the manual control for it.
 *
 * ## What "refresh" means here
 *
 * The panel is React Server Components: `router.refresh()` re-fetches this
 * route's RSC payload and re-renders it, keeping scroll position, open dialogs
 * and any client state. There is no store to reconcile — the server is the
 * store — which is why this is a handful of lines rather than a data layer.
 *
 * ## Never refresh a page nobody is looking at
 *
 * The interval stops on `document.visibilityState === "hidden"` and starts
 * again on `visibilitychange` / `focus`, with one immediate refresh on the way
 * back in: someone returning to a tab is looking at the most stale data they
 * will ever see, and making them wait out another interval for it to correct
 * itself is the wrong trade.
 *
 * ## Failure is silent
 *
 * A failed refresh leaves the rendered tree exactly as it is — RSC replaces the
 * tree only on success — and nothing is reported. The admin did not ask for
 * this refresh, so it must not take the table away or raise a banner. The
 * timestamp simply stops advancing, which is the honest signal.
 */
export function RefreshBar({
  intervalMs,
  className,
}: {
  intervalMs: number;
  className?: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  // The page was rendered on the server a moment ago, so "last updated" starts
  // at mount time. Server and client clocks differ by milliseconds, which the
  // rendered value (a Baghdad wall clock, to the minute) almost never shows —
  // suppressHydrationWarning on the element covers the boundary case.
  const [lastAt, setLastAt] = useState(() => new Date());
  const inFlight = useRef(false);

  // A hook, not a window read in an effect: this has to be available on the
  // first render, and `window` does not exist on the server.
  const beat = refreshOverrideFrom(useSearchParams().toString()) ?? intervalMs;

  const refresh = useCallback(() => {
    // Never stack: on a slow connection an interval can easily come round
    // again before the last payload has landed.
    if (inFlight.current) return;
    inFlight.current = true;
    startTransition(() => router.refresh());
  }, [router]);

  // `pending` falls back to false when the RSC payload has been applied —
  // success or failure. Either way the request is over.
  useEffect(() => {
    if (pending || !inFlight.current) return;
    inFlight.current = false;
    setLastAt(new Date());
  }, [pending]);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | undefined;
    let started = false;

    const stop = () => {
      if (timer !== undefined) clearInterval(timer);
      timer = undefined;
    };

    const sync = () => {
      const first = !started;
      started = true;
      if (document.visibilityState !== "visible") {
        stop();
        return;
      }
      // Coming back into view: catch up at once, then resume the beat. Not on
      // the very first run — the server just rendered this page.
      if (!first) refresh();
      stop();
      timer = setInterval(refresh, beat);
    };

    sync();
    document.addEventListener("visibilitychange", sync);
    window.addEventListener("focus", sync);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", sync);
      window.removeEventListener("focus", sync);
    };
  }, [beat, refresh]);

  return (
    <div className={cn("flex items-center gap-3 text-xs text-muted-foreground", className)}>
      {/* dateTime carries the machine-readable instant; the E2E suite reads it
          to prove the beat stopped while the tab was hidden and started again
          when it came back. */}
      <time
        data-testid="last-refreshed"
        dateTime={lastAt.toISOString()}
        suppressHydrationWarning
      >
        {`آخر تحديث الساعة ${formatClock(lastAt)}`}
      </time>
      <Button
        type="button"
        variant="outline"
        size="sm"
        onClick={refresh}
        disabled={pending}
        aria-label="تحديث الآن"
      >
        <RefreshCw className={cn("size-4", pending && "animate-spin")} />
        تحديث
      </Button>
    </div>
  );
}
