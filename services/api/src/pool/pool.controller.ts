import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { ClaimPoolDto, ProposeRaiseDto } from './dto/pool-actions.dto';
import { PoolService } from './pool.service';

/**
 * جانب السائق من التجميع (Phase 2) — اللوحة والاستلام واقتراح الرفع.
 *
 * **الاعتماد شرط في كل مسار هنا**، ويُفرض في الخدمة عبر
 * `DriverService.assertApprovedDriver` لا بحارس دور: «سائق» دورٌ في الـJWT،
 * بينما «معتمَد» حالةٌ في قاعدة البيانات يغيّرها الأدمن — والفرق بينهما هو
 * كل ما يقف بين حساب جديد وبين ركّاب حقيقيين في سيارته.
 */
@Controller('pools')
@UseGuards(JwtAuthGuard)
export class PoolController {
  constructor(private readonly pools: PoolService) {}

  /** اللوحة: تجمّعات جاهزة تناسب سيارتي. بلا أسماء ولا أرقام. */
  @Get('board')
  board(@CurrentUser('id') driverUserId: string) {
    return this.pools.board(driverUserId);
  }

  /** استلام تجمّع → يصير رحلة بحجوزات. أول من يستلم يأخذه. */
  @Post(':id/claim')
  @HttpCode(HttpStatus.OK)
  claim(
    @CurrentUser('id') driverUserId: string,
    @Param('id') id: string,
    @Body() dto: ClaimPoolDto,
  ) {
    return this.pools.claim(driverUserId, id, dto.departureTime);
  }

  /** اقتراح سعر أعلى — مرة واحدة، بسقف الممر، وقبل المهلة. */
  @Post(':id/raise')
  @HttpCode(HttpStatus.OK)
  proposeRaise(
    @CurrentUser('id') driverUserId: string,
    @Param('id') id: string,
    @Body() dto: ProposeRaiseDto,
  ) {
    return this.pools.proposeRaise(driverUserId, id, dto.newPricePerSeat);
  }
}
