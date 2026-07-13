import { Module } from '@nestjs/common';
import { DriverModule } from '../driver/driver.module';
import { EarningsController } from './earnings.controller';
import { EarningsService } from './earnings.service';

@Module({
  imports: [DriverModule], // findProfileByUserId → map user to their driver profile
  controllers: [EarningsController],
  providers: [EarningsService],
})
export class EarningsModule {}
