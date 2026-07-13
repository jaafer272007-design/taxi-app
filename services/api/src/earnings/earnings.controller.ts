import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { EarningsService } from './earnings.service';
import { EarningsQueryDto } from './dto/earnings-query.dto';

@Controller('driver')
@UseGuards(JwtAuthGuard)
export class EarningsController {
  constructor(private readonly earnings: EarningsService) {}

  @Get('earnings')
  get(@CurrentUser('id') userId: string, @Query() query: EarningsQueryDto) {
    return this.earnings.getEarnings(userId, query.range ?? 'all');
  }
}
