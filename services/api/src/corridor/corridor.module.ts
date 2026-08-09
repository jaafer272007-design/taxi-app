import { Module } from '@nestjs/common';
import { RolesGuard } from '../auth/guards/roles.guard';
import { CorridorController } from './corridor.controller';
import { CorridorService } from './corridor.service';
import { RouteRequestController } from './route-request.controller';
import { RouteRequestService } from './route-request.service';

@Module({
  controllers: [CorridorController, RouteRequestController],
  providers: [CorridorService, RouteRequestService, RolesGuard],
  // CorridorService: the trip module snapshots corridor price on trip creation.
  //
  // RouteRequestService lives HERE, not in `trip`, because demand is a property
  // of a corridor — it is aggregated per corridor and the admin screen it feeds
  // asks which corridors to recruit for. The trip module already imports this
  // one, so the fan-out on trip creation is a plain dependency with no cycle.
  exports: [CorridorService, RouteRequestService],
})
export class CorridorModule {}
