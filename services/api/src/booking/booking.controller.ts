import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { BookingService } from './booking.service';
import { NoShowService } from './no-show.service';
import { ChangeSeatsDto } from './dto/change-seats.dto';
import { CreateBookingDto } from './dto/create-booking.dto';

@Controller('bookings')
@UseGuards(JwtAuthGuard)
export class BookingController {
  constructor(
    private readonly bookings: BookingService,
    private readonly noShows: NoShowService,
  ) {}

  @Post()
  create(@CurrentUser('id') userId: string, @Body() dto: CreateBookingDto) {
    return this.bookings.book(userId, dto);
  }

  @Get('mine')
  mine(@CurrentUser('id') userId: string) {
    return this.bookings.listMine(userId);
  }

  /**
   * Can this rider book at all right now?
   *
   * Exists so the app can say so BEFORE the rider picks seats and pickup points
   * and then gets a 403 on submit. It is a courtesy, not a gate: `POST
   * /bookings` re-checks and refuses regardless of what the client believes.
   */
  @Get('eligibility')
  async eligibility(@CurrentUser('id') userId: string) {
    const state = await this.noShows.blockStateFor(userId);
    return {
      blocked: state.blocked,
      blockedUntil: state.blockedUntil?.toISOString() ?? null,
      noShowCount: state.countInWindow,
      threshold: this.noShows.policy.threshold,
      windowDays: this.noShows.policy.windowDays,
      message: state.blocked ? this.noShows.message(state) : null,
    };
  }

  /** Change the seat count on a live booking — the answer to "I need one more". */
  @Patch(':id')
  changeSeats(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() dto: ChangeSeatsDto,
  ) {
    return this.bookings.changeSeats(userId, id, dto.seatCount);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.bookings.cancel(userId, id);
  }

  @Post(':id/onboard')
  @HttpCode(HttpStatus.OK)
  onboard(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.bookings.onboard(userId, id);
  }

  @Post(':id/no-show')
  @HttpCode(HttpStatus.OK)
  noShow(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.bookings.noShow(userId, id);
  }
}
