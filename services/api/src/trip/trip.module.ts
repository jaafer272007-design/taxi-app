import { Module } from '@nestjs/common';
import { DriverModule } from '../driver/driver.module';
import { CorridorModule } from '../corridor/corridor.module';
import { TripController } from './trip.controller';
import { TripService } from './trip.service';

@Module({
  imports: [DriverModule, CorridorModule],
  controllers: [TripController],
  providers: [TripService],
})
export class TripModule {}
