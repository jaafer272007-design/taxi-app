import { Module } from '@nestjs/common';
import { DriverModule } from '../driver/driver.module';
import { CorridorModule } from '../corridor/corridor.module';
import { TripController } from './trip.controller';
import { TripService } from './trip.service';
import { TripContactService } from './trip-contact.service';
import { TripExpiryJob } from './trip-expiry.job';

@Module({
  imports: [DriverModule, CorridorModule],
  controllers: [TripController],
  // TripExpiryJob has no consumers — it is driven by the scheduler. It is
  // registered here so it lives next to the rule it enforces.
  providers: [TripService, TripContactService, TripExpiryJob],
})
export class TripModule {}
