import { test, expect } from "@playwright/test";

import { API_URL } from "../playwright.config";
import {
  DRIVERS,
  EDITABLE_CORRIDOR,
  EXISTING_CORRIDOR,
  FREE_CORRIDOR,
  NORMAL_ADMIN,
  SEEDED_CORRIDOR_COUNT,
  SEEDED_DRIVER_COUNT,
  SUPER_ADMIN,
  apiLogin,
  authHeader,
} from "./fixtures";

/**
 * Checks the database actually holds what the other specs assume.
 *
 * `e2e/fixtures.ts` and `services/api/prisma/seed-e2e.ts` restate the same
 * values in two packages, because importing across the package boundary would
 * drag Prisma's types into the Next build. Restating them is only safe if
 * disagreement is caught — otherwise a renamed driver or a re-taken corridor
 * pair would surface as a baffling failure three specs away, or worse, as a
 * test that still passes while asserting nothing.
 *
 * Runs in the `setup` project, BEFORE any other spec (see playwright.config.ts).
 * It has to: part of what it asserts is a pristine state — that the reserved
 * corridor pair is still free — which the create test is about to fill. Run as
 * an ordinary spec it would race that test and fail on worker timing.
 */
test.describe("seed contract", () => {
  const hint = "run `npx ts-node prisma/seed-e2e.ts` in services/api against this database";

  test("both admin roles exist and can log in", async ({ request }) => {
    const superToken = await apiLogin(request, SUPER_ADMIN);
    const adminToken = await apiLogin(request, NORMAL_ADMIN);

    const superMe = await request.get(`${API_URL}/admin/auth/me`, {
      headers: authHeader(superToken),
    });
    expect(await superMe.json(), hint).toMatchObject({
      username: SUPER_ADMIN.username,
      role: "SUPER_ADMIN",
    });

    const adminMe = await request.get(`${API_URL}/admin/auth/me`, {
      headers: authHeader(adminToken),
    });
    expect(await adminMe.json(), hint).toMatchObject({
      username: NORMAL_ADMIN.username,
      role: "ADMIN",
    });
  });

  test("the reserved corridor pairs are in the state the tests need", async ({ request }) => {
    const token = await apiLogin(request, NORMAL_ADMIN);
    const res = await request.get(`${API_URL}/corridors`, { headers: authHeader(token) });
    const corridors = (await res.json()) as {
      originCity: string;
      destCity: string;
      suggestedPricePerSeat: number;
    }[];

    const find = (o: string, d: string) =>
      corridors.find((c) => c.originCity === o && c.destCity === d);

    // The full 18x17 grid minus the two freed pairs. Checked here — before any
    // spec has created anything — because a partially seeded grid would
    // otherwise surface as a baffling pagination or search-count failure rather
    // than as "the seed didn't finish".
    expect(corridors.length, `expected the full corridor grid — ${hint}`).toBe(
      SEEDED_CORRIDOR_COUNT,
    );

    // Must be ABSENT: the create test needs a free pair, and the grid otherwise
    // occupies all 306.
    expect(
      find(FREE_CORRIDOR.origin, FREE_CORRIDOR.dest),
      `${FREE_CORRIDOR.origin}→${FREE_CORRIDOR.dest} should be free for the create test — ${hint}`,
    ).toBeUndefined();

    // Must be PRESENT: the duplicate test needs a pair that is already taken.
    expect(
      find(EXISTING_CORRIDOR.origin, EXISTING_CORRIDOR.dest),
      `${EXISTING_CORRIDOR.origin}→${EXISTING_CORRIDOR.dest} should exist — ${hint}`,
    ).toBeDefined();

    // Must be at its seeded price, or the edit test cannot tell a successful
    // save from a no-op.
    expect(
      find(EDITABLE_CORRIDOR.origin, EDITABLE_CORRIDOR.dest)?.suggestedPricePerSeat,
      `${EDITABLE_CORRIDOR.origin}→${EDITABLE_CORRIDOR.dest} should start at its seeded price — ${hint}`,
    ).toBe(EDITABLE_CORRIDOR.suggested);
  });

  test("every fixture driver exists with the name the tests look for", async ({ request }) => {
    const token = await apiLogin(request, NORMAL_ADMIN);
    const res = await request.get(`${API_URL}/admin/drivers`, { headers: authHeader(token) });
    const drivers = (await res.json()) as { user: { phone: string; name: string } | null }[];

    expect(drivers.length, `expected ${SEEDED_DRIVER_COUNT} seeded drivers — ${hint}`).toBe(
      SEEDED_DRIVER_COUNT,
    );

    for (const [key, fixture] of Object.entries(DRIVERS)) {
      const match = drivers.find((d) => d.user?.phone === fixture.phone);
      expect(match, `driver fixture "${key}" (${fixture.phone}) is missing — ${hint}`).toBeDefined();
      expect(match!.user?.name, `driver fixture "${key}" has a different name — ${hint}`).toBe(
        fixture.name,
      );
    }
  });

  test("the never-mutated drivers still hold their seeded status", async ({ request }) => {
    // These two back the status-filter assertions, so if some other test starts
    // touching them the filter spec would quietly stop proving anything.
    const token = await apiLogin(request, NORMAL_ADMIN);
    const res = await request.get(`${API_URL}/admin/drivers`, { headers: authHeader(token) });
    const drivers = (await res.json()) as { status: string; user: { phone: string } | null }[];

    for (const fixture of [DRIVERS.rejected, DRIVERS.stable]) {
      const match = drivers.find((d) => d.user?.phone === fixture.phone);
      expect(
        match?.status,
        `${fixture.name} must stay ${fixture.status} — no test may act on it. ${hint}`,
      ).toBe(fixture.status);
    }
  });
});
