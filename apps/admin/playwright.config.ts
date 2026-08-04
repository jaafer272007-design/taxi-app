import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end tests for the admin panel.
 *
 * The panel is the only surface in the repo with no automated coverage, and it
 * is the one that prices corridors and approves drivers — so these run against
 * a REAL stack (Postgres + Redis + the NestJS API + a production Next build),
 * not against mocks. A mocked backend would happily pass while the actual
 * role separation was broken.
 *
 * ## Before running
 *
 * The database must exist, be migrated, and be seeded:
 *
 *     cd services/api
 *     npx prisma migrate deploy
 *     npx ts-node prisma/seed-e2e.ts
 *
 * Then `npm run e2e` from apps/admin. Playwright starts both servers itself
 * (see `webServer`), so the two run identically here and in CI.
 *
 * ## Ports
 *
 * The API owns 3000 (its default, and what `API_BASE_URL` points at), so the
 * panel is served on 3100 rather than colliding with it.
 */

const API_PORT = Number(process.env.E2E_API_PORT ?? 3000);
const ADMIN_PORT = Number(process.env.E2E_ADMIN_PORT ?? 3100);

export const API_URL = `http://127.0.0.1:${API_PORT}`;
export const ADMIN_URL = `http://127.0.0.1:${ADMIN_PORT}`;

/** Where the signed-in browser states from `auth.setup.ts` are cached. */
export const STORAGE_STATE_DIR = "e2e/.auth";

export default defineConfig({
  testDir: "./e2e",
  // A suite that has to be run with a flag to be trusted is a suite nobody
  // runs. Everything here must pass unattended, every time.
  forbidOnly: !!process.env.CI,
  // Zero retries locally so a flaky test is visible immediately; one in CI so a
  // genuine infrastructure blip doesn't red-flag an innocent PR. A test that
  // needs the retry to pass is a bug to fix, not a cost to absorb.
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: process.env.CI
    ? [["list"], ["html", { outputFolder: "playwright-report", open: "never" }]]
    : [["list"]],

  // Generous enough for a cold Next.js route compile, tight enough that a hang
  // fails the build instead of burning the job's wall clock.
  timeout: 45_000,
  expect: { timeout: 10_000 },

  use: {
    baseURL: ADMIN_URL,
    // Kept on the first retry (and always for a failure in CI) so a red run is
    // diagnosable from the uploaded artifact without a local reproduction.
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    locale: "ar-IQ",
    timezoneId: "Asia/Baghdad",
  },

  projects: [
    // Runs before everything else. Two jobs: cache a signed-in session per role
    // (so the other specs don't drive the login form 30 times), and check the
    // database holds the fixtures the suite assumes.
    //
    // The seed check has to live HERE rather than beside the other specs
    // because part of what it asserts is a PRISTINE state — that the reserved
    // corridor pair is still free. Run as an ordinary test it would race the
    // create test that fills that pair, and fail depending on worker timing.
    { name: "setup", testMatch: /(auth\.setup|seed-contract\.spec)\.ts/ },
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
      testIgnore: /seed-contract\.spec\.ts/,
      dependencies: ["setup"],
    },
  ],

  webServer: [
    {
      command: "node dist/main.js",
      cwd: "../../services/api",
      url: `${API_URL}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      stdout: "pipe",
      stderr: "pipe",
    },
    {
      // A production build, matching what actually ships. `next dev` has
      // different error handling and compile timing, so testing it would test
      // something nobody deploys.
      command: `npx next start -p ${ADMIN_PORT}`,
      url: ADMIN_URL,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
      stdout: "pipe",
      stderr: "pipe",
      env: { API_BASE_URL: API_URL },
    },
  ],
});
