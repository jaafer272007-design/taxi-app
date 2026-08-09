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
  // NoShowService: the admin module needs it for the appeal path (history /
  // void / lift), and the trip module for the count beside each passenger.
  //
  // BookingService: an admin cancelling a booking on a rider's behalf runs
  // THIS method — the row-locked seat return, the LOCKED→OPEN reopen and both
  // notifications. Exporting it is what keeps the support tools from growing
  // their own copy of the seat transaction.
  exports: [NoShowService, BookingService],
})
export class BookingModule {}
