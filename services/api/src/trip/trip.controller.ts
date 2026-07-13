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
import { TripService } from './trip.service';
import { CreateTripDto } from './dto/create-trip.dto';
import { UpdateTripDto } from './dto/update-trip.dto';

@Controller('trips')
@UseGuards(JwtAuthGuard)
export class TripController {
  constructor(private readonly trips: TripService) {}

  @Post()
  createTrip(@CurrentUser('id') userId: string, @Body() dto: CreateTripDto) {
    return this.trips.createTrip(userId, dto);
  }

  @Get('mine')
  listMine(@CurrentUser('id') userId: string) {
    return this.trips.listMine(userId);
  }

  @Patch(':id')
  updateTrip(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() dto: UpdateTripDto,
  ) {
    return this.trips.updateTrip(userId, id, dto);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancelTrip(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.trips.cancelTrip(userId, id);
  }
}
