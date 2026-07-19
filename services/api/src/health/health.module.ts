import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';

/** Liveness probe module (no providers — the controller is dependency-free). */
@Module({ controllers: [HealthController] })
export class HealthModule {}
