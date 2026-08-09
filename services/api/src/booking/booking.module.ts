import { Module } from '@nestjs/common';
import { DriverModule } from '../driver/driver.module';
import { BookingController } from './booking.controller';
import { TripSearchController } from './trip-search.controller';
import { BookingService } from './booking.service';
import { NoShowService } from './no-show.service';

@Module({
  imports: [DriverModule], // findProfileByUserId → "can't book your own trip" check
  controllers: [BookingController, TripSearchController],
  providers: [BookingService, NoShowService],
  // The admin module needs it for the appeal path (history / void / lift), and
  // the trip module for the count beside each passenger.
  exports: [NoShowService],
})
export class BookingModule {}
