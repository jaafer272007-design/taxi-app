import { Module } from '@nestjs/common';
import { DriverModule } from '../driver/driver.module';
import { CorridorModule } from '../corridor/corridor.module';
import { BookingModule } from '../booking/booking.module';
import { TripController } from './trip.controller';
import { TripService } from './trip.service';
import { TripContactService } from './trip-contact.service';
import { TripExpiryJob } from './trip-expiry.job';

@Module({
  // BookingModule exports NoShowService — the count beside each passenger on
  // the driver's bookings list comes from the same records the booking module
  // writes, not a second tally.
  imports: [DriverModule, CorridorModule, BookingModule],
  controllers: [TripController],
  // TripExpiryJob has no consumers — it is driven by the scheduler. It is
  // registered here so it lives next to the rule it enforces.
  providers: [TripService, TripContactService, TripExpiryJob],
})
export class TripModule {}
