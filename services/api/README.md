# Taxi API (`services/api`)

NestJS modular monolith + Prisma. **Phase 1, Step 1: Scaffold + DB + Auth.**
See `../../docs/PHASE1_BUILD_BRIEF.md` and the root `CLAUDE.md` for scope and the
hard "don't build Phase 2" barriers.

## Stack
NestJS 11 · Prisma 6 · PostgreSQL (PostGIS available, unused in Phase 1) · Redis ·
JWT auth · WhatsApp Business Cloud API for OTP.

## Local setup

```bash
cp .env.example .env            # fill in values (WhatsApp vars optional in dev)
docker compose up -d            # Postgres (postgis) + Redis
npm install
npm run prisma:generate
npm run prisma:migrate          # applies the initial migration
npm run start:dev               # http://localhost:3000
```

If you don't use Docker, point `DATABASE_URL` / `REDIS_URL` at your own
Postgres + Redis.

## Auth endpoints (Phase 1, Step 1)

| Method | Path                | Body                     | Notes |
|--------|---------------------|--------------------------|-------|
| POST   | `/auth/request-otp` | `{ phone }`              | +964 only. Rate-limited: 3 / 10 min per phone. |
| POST   | `/auth/verify-otp`  | `{ phone, code }`        | Creates the user if new (default role `RIDER`), returns a JWT. |
| GET    | `/auth/me`          | —                        | `Authorization: Bearer <jwt>`. Returns the authenticated user. |

## Driver + admin endpoints (Phase 1, Step 2)

All require `Authorization: Bearer <jwt>`. Admin routes also require the `ADMIN` role (RolesGuard).

| Method | Path                          | Body / form                                   | Notes |
|--------|-------------------------------|-----------------------------------------------|-------|
| POST   | `/driver/profile`             | —                                             | Become a driver: creates a `PENDING` profile, grants the `DRIVER` role. |
| POST   | `/driver/vehicle`             | `{ make, model, plate, color, seats }`        | Adds/replaces the driver's vehicle. |
| POST   | `/driver/documents`           | multipart: `file`, `type`                     | `type` ∈ `NATIONAL_ID \| DRIVING_LICENSE \| VEHICLE_REG`. Stored under `UPLOAD_DIR` in dev. |
| GET    | `/driver/profile`             | —                                             | Profile + vehicle + documents + status. |
| GET    | `/admin/drivers?status=`      | —                                             | ADMIN only. Filter by `DriverStatus`. Returns drivers + docs. |
| POST   | `/admin/drivers/:id/approve`  | —                                             | ADMIN only. → `APPROVED`. |
| POST   | `/admin/drivers/:id/reject`   | `{ reason? }`                                 | ADMIN only. → `REJECTED`. |
| POST   | `/admin/drivers/:id/suspend`  | —                                             | ADMIN only. → `SUSPENDED`. |

Only an **APPROVED** driver may post trips (enforced in `DriverService.assertApprovedDriver`,
which the trip module will call in Step 3). Non-admins hitting `/admin/*` get `403`.

### Seed an admin
```bash
ADMIN_PHONE=+9647700000000 npm run prisma:seed
```
Creates one `ADMIN` user. The admin logs in through the normal OTP flow and receives an ADMIN-role JWT.

### OTP delivery
Codes are sent via the WhatsApp Business Cloud API. **DEV fallback:** if any of
`WHATSAPP_PHONE_NUMBER_ID` / `WHATSAPP_ACCESS_TOKEN` / `WHATSAPP_OTP_TEMPLATE` is
missing, the code is logged to the console instead — labelled `DEV-ONLY` and a
**hard release blocker**. That mode is refused when `NODE_ENV=production`.

## Tests
```bash
npm test                        # unit tests (e.g. Iraqi phone normalization)
```

## Constants (non-negotiable — see root CLAUDE.md)
IQD integer amounts · `TZ=Asia/Baghdad` · Arabic user-facing strings · JWT auth ·
identity = +964 mobile via WhatsApp OTP.
