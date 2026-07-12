import { Module } from '@nestjs/common';
import { StorageModule } from '../storage/storage.module';
import { DriverController } from './driver.controller';
import { DriverService } from './driver.service';

@Module({
  imports: [StorageModule],
  controllers: [DriverController],
  providers: [DriverService],
  // Exported so the trip module (Step 3) can call assertApprovedDriver().
  exports: [DriverService],
})
export class DriverModule {}
