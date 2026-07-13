import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { RatingService } from './rating.service';
import { CreateRatingDto } from './dto/create-rating.dto';

@Controller('ratings')
@UseGuards(JwtAuthGuard)
export class RatingController {
  constructor(private readonly ratings: RatingService) {}

  @Post()
  create(@CurrentUser('id') userId: string, @Body() dto: CreateRatingDto) {
    return this.ratings.create(userId, dto);
  }

  @Get('user/:id')
  byUser(@Param('id') id: string) {
    return this.ratings.getUserRatings(id);
  }
}
