-- Driver-set pricing (Phase 1 amendment).
--
-- The corridor price stops being the fare and becomes a SUGGESTION, bracketed by
-- an admin-set [min, max] band. The driver picks the actual price per seat when
-- posting a trip; Trip.pricePerSeat keeps its meaning (the snapshot the fare is
-- computed from), only its source changes.

-- 1. The old admin price IS the suggestion — rename, don't drop, so no existing
--    corridor loses its price.
ALTER TABLE "Corridor" RENAME COLUMN "pricePerSeat" TO "suggestedPricePerSeat";

-- 2. Nullable first, so the backfill can run before NOT NULL is asserted.
ALTER TABLE "Corridor" ADD COLUMN "minPricePerSeat" INTEGER;
ALTER TABLE "Corridor" ADD COLUMN "maxPricePerSeat" INTEGER;

-- 3. Backfill a DELIBERATELY WIDE default band around the existing price:
--      min = 50% of the suggestion, rounded DOWN to the nearest 250 IQD
--      max = 200% of the suggestion, rounded UP   to the nearest 250 IQD
--    250 IQD is the smallest note in everyday circulation, so a band edge always
--    lands on a payable amount.
--
--    Why so wide: this migration must not retroactively invalidate a price a
--    driver would plausibly set on day one. A narrow band would turn a data
--    migration into a silent product decision. The admin narrows it per corridor
--    from the panel, where the change is deliberate and visible.
--
--    LEAST/GREATEST pin the invariant min <= suggested <= max for every possible
--    existing value — including tiny prices, where the rounding alone would
--    otherwise push min above (or max below) the suggestion.
UPDATE "Corridor" SET
  "minPricePerSeat" = LEAST(
    "suggestedPricePerSeat",
    GREATEST(250, FLOOR("suggestedPricePerSeat" / 500.0)::int * 250)
  ),
  "maxPricePerSeat" = GREATEST(
    "suggestedPricePerSeat",
    CEIL("suggestedPricePerSeat" / 125.0)::int * 250
  );

ALTER TABLE "Corridor" ALTER COLUMN "minPricePerSeat" SET NOT NULL;
ALTER TABLE "Corridor" ALTER COLUMN "maxPricePerSeat" SET NOT NULL;

-- 4. Backstop the invariant in the database itself. CorridorService validates it
--    first and returns the Arabic 400; this only catches a write that bypasses
--    the service (a seed script, a manual psql session).
--    Prisma cannot express CHECK constraints in schema.prisma, so it lives here.
--    That is safe for `migrate deploy` and for the shadow database `migrate dev`
--    builds, since both replay this file.
ALTER TABLE "Corridor" ADD CONSTRAINT "Corridor_price_band_check" CHECK (
  "minPricePerSeat" > 0
  AND "minPricePerSeat" <= "suggestedPricePerSeat"
  AND "suggestedPricePerSeat" <= "maxPricePerSeat"
);

-- Trip.pricePerSeat is intentionally untouched: existing trips keep the exact
-- price they were posted at, and every existing booking keeps its fare.
