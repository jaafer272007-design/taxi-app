# Running the Taxi API locally (alongside Aurora)

This backend runs in Docker on **deliberately non-default ports** so it can share a
machine with another local stack (e.g. **Aurora**) with **zero collisions**.

| Resource        | Taxi (this app)              | Default / typical Aurora |
| --------------- | ---------------------------- | ------------------------ |
| Postgres host port | **5433** → container 5432 | 5432                     |
| Redis host port    | **6380** → container 6379 | 6379                     |
| Compose project    | `taxi`                    | (its own)                |
| Containers         | `taxi_postgres`, `taxi_redis` | (its own)            |
| Database name      | `taxi_db`                 | (its own)                |
| Named volumes      | `taxi_pgdata`, `taxi_redisdata` | (its own)          |
| Docker network     | `taxi_default`            | (its own)                |

Nothing above is shared with any other project, so **both stacks can run at once**.

---

## Prerequisites
- Docker (with `docker compose` v2)
- Node.js 20+ and npm

## 1. Start the taxi infra (Postgres + Redis)
From `services/api/`:

> **Ran an older revision of this file before?** Do the one-time cleanup in
> [Upgrading from an earlier version](#upgrading-from-an-earlier-version-of-this-compose-file)
> **first** — the old `taxi_redis` container shares its name and would block this step.

```bash
cd services/api
docker compose up -d
```

This starts:
- `taxi_postgres` on **localhost:5433** (db `taxi_db`, user/pass `taxi`/`taxi`)
- `taxi_redis` on **localhost:6380**

Check both are healthy:

```bash
docker compose ps
```

## 2. Configure the environment
The committed template already points at the ports above. Copy it once:

```bash
cp .env.example .env
```

Key values (already set in `.env.example`):

```
DATABASE_URL="postgresql://taxi:taxi@localhost:5433/taxi_db?schema=public"
REDIS_URL="redis://localhost:6380"
```

> **OTP in dev (no WhatsApp yet):** leave the three `WHATSAPP_*` vars **empty**.
> With WhatsApp unconfigured, the server **prints the login code to its own logs**
> instead of sending it — that is the dev fallback (there is no separate
> `OTP_DEV_LOG` flag; empty WhatsApp config *is* the switch). See step 5.

## 3. Install deps, generate the client, apply migrations
From `services/api/`:

```bash
npm ci
npm run prisma:generate
npm run prisma:migrate:deploy
npm run prisma:seed   # optional: creates the admin user + Najaf↔Karbala corridors
```

## 4. Start the API

```bash
npm run start:dev
```

It listens on **http://localhost:3000** and logs:

```
[Bootstrap] Taxi API listening on :3000 (TZ=Asia/Baghdad)
```

## 5. Confirm it's running + read the OTP

**Health check** (liveness — no auth):

```bash
curl http://localhost:3000/health
# → {"status":"ok","service":"taxi-api","tz":"Asia/Baghdad","time":"…"}
```

**Log in / read the OTP from the logs.** Request a code:

```bash
curl -X POST http://localhost:3000/auth/request-otp \
  -H 'Content-Type: application/json' \
  -d '{"phone":"+9647701234567"}'
```

Then read the code from the **server console** (the `npm run start:dev` window):

```
[WARN] [DEV-ONLY][RELEASE BLOCKER] WhatsApp not configured — OTP for +9647701234567 is 123456. …
```

Verify it to get a JWT:

```bash
curl -X POST http://localhost:3000/auth/verify-otp \
  -H 'Content-Type: application/json' \
  -d '{"phone":"+9647701234567","code":"123456"}'
```

## Handy: connect a client for debugging
- **Postgres:** host `localhost`, port `5433`, db `taxi_db`, user `taxi`, pass `taxi`
  (e.g. `psql "postgresql://taxi:taxi@localhost:5433/taxi_db"`)
- **Redis:** `redis-cli -p 6380 ping` → `PONG`

## Running the admin panel's E2E suite

The Playwright suite in `apps/admin/e2e` drives the panel against a **real** API,
Postgres and Redis. It is destructive over the rows it owns, so point it at a
**throwaway database** — never `taxi_db`.

```bash
# 1. A database for the suite alone.
psql "postgresql://taxi:taxi@localhost:5433/postgres" -c "CREATE DATABASE taxi_e2e;"

# 2. Migrate + seed it. Prisma reads services/api/.env, and that file WINS over
#    an exported DATABASE_URL — so override it there (or use a separate env
#    file) rather than exporting the variable and assuming it took effect.
cd services/api
DATABASE_URL="postgresql://taxi:taxi@localhost:5433/taxi_e2e?schema=public" \
SUPER_ADMIN_USERNAME=e2e-superadmin SUPER_ADMIN_PASSWORD=e2e-password-1234 \
  npx prisma migrate deploy
# …then the E2E fixtures (super admin, a normal admin, drivers, corridors):
npx ts-node prisma/seed-e2e.ts

# 3. Build both apps, then run. Playwright starts the API and the panel itself.
npm run build
cd ../../apps/admin && npm run build && npm run e2e
```

Re-run the seed between runs: the suite approves drivers, edits prices and
creates a corridor, and the seed is what puts those back. It also clears the
admin-login throttle counters in Redis, which otherwise outlive the run by 15
minutes and make the rate-limit test fail on a second run.

`npm run e2e:report` opens the HTML report; a failing CI run uploads the same
traces as the `admin-e2e-failures` artifact.

## Stop / reset

```bash
docker compose down        # stop containers, keep data
docker compose down -v      # stop AND delete the taxi volumes (fresh DB next up)
```

`down -v` only removes the `taxi_*` volumes — **it never touches Aurora's data.**

### Upgrading from an earlier version of this compose file
An earlier revision used the default ports (5432/6379) and DB `taxi_dev`. Its Postgres
container was named `taxi_db` (this version renames it to `taxi_postgres`), but the
**Redis container name is unchanged (`taxi_redis`)**. So if you ran that older version,
do a **one-time cleanup BEFORE your first `docker compose up`** of this version —
otherwise the leftover old `taxi_redis` container will conflict with the new one.

Discover and remove the old objects (their exact volume names depend on the old
project name, so list them rather than guessing):

```bash
# BEFORE `docker compose up` — only if you ran an older revision.
docker ps -a  | grep -E 'taxi_db|taxi_redis'   # old containers (taxi_db, taxi_redis)
docker rm -f taxi_db taxi_redis 2>/dev/null || true

docker volume ls | grep -i taxi                # old volumes (e.g. api_taxi_db_data)
# then remove the ones it prints, e.g.:
# docker volume rm api_taxi_db_data api_taxi_redis_data
```

Removing them is safe — they hold no data you need for a fresh start, and none of it
is shared with Aurora.


---

## Running the polling lifecycle E2E (real browser)

`apps/rider/e2e/polling_lifecycle.mjs` is the regression guard for the bug where
**every poll in the app died the moment the window lost focus** — clicking over
to the driver app was enough. It is the only test that can catch that class of
problem, because a widget test decides for itself what
`AppLifecycleState.inactive` means; only a real engine knows a browser blur *is*
`inactive`. CI runs it as the `apps/rider (polling lifecycle, real browser)` job.

To run it locally you need the API up (steps 1–3 above), with its output going to
a file — the dev OTP fallback prints the code there and the test reads it:

```bash
cd services/api && node dist/main.js > /tmp/api.log 2>&1 &

# The web build. --no-web-resources-cdn keeps CanvasKit local (no gstatic
# fetch); --pwa-strategy=none stops a stale service worker serving an old
# bundle. The API_BASE_URL define is REQUIRED: the default is the Android
# emulator alias 10.0.2.2, which a browser cannot route to.
cd apps/rider
flutter build web --release --pwa-strategy=none --no-web-resources-cdn \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000
(cd build/web && python3 -m http.server 8088 --bind 127.0.0.1 &)

cd e2e && npm install && npx playwright install chromium
API_LOG=/tmp/api.log node polling_lifecycle.mjs
```

It logs in through the real OTP flow, then measures `GET /notifications` across
three ~70s windows — focused, blurred, refocused — and fails if the middle one
is silent. Takes about four minutes.

> `apps/rider/web/` exists **for this test**. Phase 1 ships Android only; the web
> target is a test harness, not a shipping platform.
