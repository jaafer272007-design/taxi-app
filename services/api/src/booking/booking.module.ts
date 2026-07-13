import { Module } from '@nestjs/common';
import { DriverModule } from '../driver/driver.module';
import { BookingController } from './booking.controller';
import { TripSearchController } from './trip-search.controller';
import { BookingService } from './booking.service';

@Module({
  imports: [DriverModule], // findProfileByUserId → "can't book your own trip" check
  controllers: [BookingController, TripSearchController],
  providers: [BookingService],
})
export class BookingModule {}
