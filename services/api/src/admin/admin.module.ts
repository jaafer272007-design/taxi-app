import { Module } from '@nestjs/common';
import { RolesGuard } from '../auth/guards/roles.guard';
import { AdminController } from './admin.controller';
import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminService } from './admin.service';

@Module({
  controllers: [AdminController, AdminDashboardController],
  providers: [AdminService, RolesGuard],
})
export class AdminModule {}
