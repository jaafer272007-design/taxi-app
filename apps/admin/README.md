# apps/admin — Admin panel (Phase 1)

Next.js 16 (App Router, Turbopack), Arabic RTL, Tailwind v4 + shadcn/ui-style
components. Talks to the `services/api` NestJS backend over HTTP — no
database access of its own.

## Status (Phase 1)

Corridor management is implemented end-to-end:

- **Auth** — admin logs in with the same WhatsApp-OTP flow as the rider/driver
  apps (`/auth/request-otp`, `/auth/verify-otp` on the backend). The JWT lives
  only in an httpOnly session cookie set by this app's own Route Handlers
  (`src/app/api/auth/*`); browser JS never touches it. Non-`ADMIN` accounts are
  refused a session at login, and the corridors layout re-checks the role on
  every request in case a cookie for this app was ever set to a non-admin
  token by hand.
- **Corridors** — list, create, edit (price/route), and activate/deactivate
  corridors between any of Iraq's 18 governorate capitals
  (`src/lib/cities.ts`, kept in sync with `services/api/src/corridor/cities.ts`
  and `packages/shared/lib/constants/iraqi_cities.dart`). Validation mirrors
  the backend: same city twice is rejected, duplicate `(origin, dest)` pairs
  surface the backend's 409 as an inline Arabic error, and price must be a
  positive integer (IQD has no fractional unit).
- **Design tokens** — colors/typography/spacing/radius are read from
  `src/app/globals.css`, itself sourced from
  `packages/shared/lib/theme/*.dart` so the admin panel matches the rider/
  driver apps' palette in both light and dark.
- Not yet built: driver approval/document review, trip monitoring, and basic
  support tooling (see `docs/PHASE1_BUILD_BRIEF.md` §5, admin screens 1/2/3/5).

## Run

```bash
cd apps/admin
npm install
cp .env.example .env.local   # set API_BASE_URL if the backend isn't on :3000
npm run dev                  # http://localhost:3000 by default — change the port
                              # if services/api is already using it
```

Requires `services/api` running with an `ADMIN`-role user to log in as (see
`docs/RUN_LOCAL.md` for standing up the backend + seed data).

## shadcn/ui components

`src/components/ui/*` are hand-authored to match shadcn's canonical source
rather than pulled via `npx shadcn add` — the CLI's registry fetch
(`ui.shadcn.com`) is blocked by this environment's egress policy. If that's no
longer the case, `components.json` is already configured for the CLI to take
over normally.
