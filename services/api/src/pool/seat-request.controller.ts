import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { CreateSeatRequestDto } from './dto/create-seat-request.dto';
import { RespondToRaiseDto } from './dto/pool-actions.dto';
import { PoolService } from './pool.service';
import { SeatRequestService } from './seat-request.service';

/**
 * جانب الراكب من التجميع (Phase 2).
 *
 * كل مسار هنا يعمل على **طلب الراكب نفسه** — الملكية تُفحص في الخدمة من
 * `riderId` القادم من الـJWT، لا من الجسم.
 */
@Controller('seat-requests')
@UseGuards(JwtAuthGuard)
export class SeatRequestController {
  constructor(
    private readonly seatRequests: SeatRequestService,
    private readonly pools: PoolService,
  ) {}

  /** «أريد مقعداً على هذا الممر بين هذين الوقتين». */
  @Post()
  create(@CurrentUser('id') riderId: string, @Body() dto: CreateSeatRequestDto) {
    return this.seatRequests.create(riderId, dto);
  }

  /** طلباتي وحالتها. */
  @Get('mine')
  listMine(@CurrentUser('id') riderId: string) {
    return this.seatRequests.listMine(riderId);
  }

  /**
   * إلغاء طلب لم يُستلم بعد.
   *
   * بعد الاستلام صار حجزاً — يُلغى من `DELETE /bookings/:id` بكل قواعده.
   */
  @Delete(':id')
  cancel(@CurrentUser('id') riderId: string, @Param('id') id: string) {
    return this.seatRequests.cancel(riderId, id);
  }

  /** الردّ على اقتراح رفع السعر. الرفض بلا أي عقوبة. */
  @Post(':id/raise-response')
  @HttpCode(HttpStatus.OK)
  respondToRaise(
    @CurrentUser('id') riderId: string,
    @Param('id') id: string,
    @Body() dto: RespondToRaiseDto,
  ) {
    return this.pools.respondToRaise(riderId, id, dto.accept);
  }
}
