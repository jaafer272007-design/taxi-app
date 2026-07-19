import { Controller, Get } from '@nestjs/common';

/**
 * Liveness probe (`GET /health`). Ops-only: it touches no database, Redis, or
 * business logic, so it answers 200 as long as the HTTP server is up. Used by
 * `docker`/scripts/humans to confirm the API is running (see docs/RUN_LOCAL.md).
 * It is intentionally public (no auth) so a bare `curl` works.
 */
@Controller('health')
export class HealthController {
  @Get()
  check(): { status: string; service: string; tz: string; time: string } {
    return {
      status: 'ok',
      service: 'taxi-api',
      tz: process.env.TZ ?? 'Asia/Baghdad',
      time: new Date().toISOString(),
    };
  }
}
