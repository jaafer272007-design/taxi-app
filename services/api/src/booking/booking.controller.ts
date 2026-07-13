import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { BookingService } from './booking.service';
import { CreateBookingDto } from './dto/create-booking.dto';

@Controller('bookings')
@UseGuards(JwtAuthGuard)
export class BookingController {
  constructor(private readonly bookings: BookingService) {}

  @Post()
  create(@CurrentUser('id') userId: string, @Body() dto: CreateBookingDto) {
    return this.bookings.book(userId, dto);
  }

  @Get('mine')
  mine(@CurrentUser('id') userId: string) {
    return this.bookings.listMine(userId);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.bookings.cancel(userId, id);
  }
}
