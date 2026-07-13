import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { BookingService } from './booking.service';
import { SearchTripsDto } from './dto/search-trips.dto';

/**
 * Rider-facing trip search. Lives in the booking module (part of the booking
 * flow) but is exposed under /trips/search per the brief.
 */
@Controller('trips')
@UseGuards(JwtAuthGuard)
export class TripSearchController {
  constructor(private readonly bookings: BookingService) {}

  @Get('search')
  search(@Query() dto: SearchTripsDto) {
    return this.bookings.search(dto);
  }
}
