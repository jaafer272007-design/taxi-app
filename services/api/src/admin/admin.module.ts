import { Module } from '@nestjs/common';
import { RolesGuard } from '../auth/guards/roles.guard';
import { BookingModule } from '../booking/booking.module';
import { AdminController } from './admin.controller';
import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminNoShowController } from './admin-no-show.controller';
import { AdminService } from './admin.service';

@Module({
  // NoShowService lives with the booking module that writes the records; the
  // appeal path reads and voids them rather than owning a second copy of the
  // rule.
  imports: [BookingModule],
  controllers: [AdminController, AdminDashboardController, AdminNoShowController],
  providers: [AdminService, RolesGuard],
})
export class AdminModule {}
