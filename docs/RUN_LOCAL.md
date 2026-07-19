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

