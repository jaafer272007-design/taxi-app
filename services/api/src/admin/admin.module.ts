import { Module } from '@nestjs/common';
import { RolesGuard } from '../auth/guards/roles.guard';
import { BookingModule } from '../booking/booking.module';
import { CorridorModule } from '../corridor/corridor.module';
import { TripModule } from '../trip/trip.module';
import { AdminController } from './admin.controller';
import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminNoShowController } from './admin-no-show.controller';
import { AdminRouteRequestController } from './admin-route-request.controller';
import { AdminSupportController } from './admin-support.controller';
import { AdminAuditService } from './admin-audit.service';
import { AdminService } from './admin.service';
import { AdminSupportService } from './admin-support.service';

@Module({
  // NoShowService lives with the booking module that writes the records; the
  // appeal path reads and voids them rather than owning a second copy of the
  // rule.
  //
  // BookingModule + TripModule are imported for the SAME reason the support
  // tools exist at all: an admin intervention runs the app's own service
  // method — the seat transaction, the state machine, the notification
  // fan-out — instead of writing state behind them.
  //
  // CorridorModule exports RouteRequestService for the same reason: the demand
  // aggregate reads the rows the rider path writes, rather than owning a
  // second copy of the window rule.
  imports: [BookingModule, CorridorModule, TripModule],
  controllers: [
    AdminController,
    AdminDashboardController,
    AdminNoShowController,
    AdminRouteRequestController,
    AdminSupportController,
  ],
  providers: [AdminService, AdminSupportService, AdminAuditService, RolesGuard],
})
export class AdminModule {}
