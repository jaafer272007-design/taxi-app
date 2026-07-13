import { Module } from '@nestjs/common';
import { RolesGuard } from '../auth/guards/roles.guard';
import { CorridorController } from './corridor.controller';
import { CorridorService } from './corridor.service';

@Module({
  controllers: [CorridorController],
  providers: [CorridorService, RolesGuard],
  // Exported so the trip module can snapshot corridor price on trip creation.
  exports: [CorridorService],
})
export class CorridorModule {}
