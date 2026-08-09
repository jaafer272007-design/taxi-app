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
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { NoShowService } from '../booking/no-show.service';
import { VoidNoShowDto } from './dto/void-no-show.dto';

/**
 * مسار التظلّم على عدم الحضور.
 *
 * **هذا الجزء ليس تكميلياً.** الإيقاف التلقائي بلا طريق للمراجعة يعني أن ظرفاً
 * طارئاً حقيقياً — مستشفى، عزاء، عطل — يساوي حظراً. الأدمن هنا يقدر:
 *
 *  - يقرأ تاريخ راكب كاملاً (بما فيه الملغى)،
 *  - يُلغي واقعة واحدة إذا كان لها عذر،
 *  - يرفع الإيقاف كلّه دفعةً واحدة،
 *
 * وكل عملية **تُسجَّل بسببها وبمَن نفّذها**. السبب مطلوب لا اختياري: قرار بلا
 * سبب مكتوب لا يمكن مراجعته لاحقاً ولا تعلّم منه السياسة.
 */
@Controller('admin/no-shows')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN)
export class AdminNoShowController {
  constructor(private readonly noShows: NoShowService) {}

  /** الركّاب الموقوفون الآن + الأرقام السارية، حتى تكون السياسة مرئية. */
  @Get('blocked')
  async blocked() {
    const rows = await this.noShows.blockedRiders();
    return {
      policy: this.noShows.policy,
      riders: rows.map((r) => ({
        riderId: r.rider?.id ?? null,
        name: r.rider?.name ?? null,
        phone: r.rider?.phone ?? null,
        noShowCount: r.state.countInWindow,
        blockedUntil: r.state.blockedUntil?.toISOString() ?? null,
      })),
    };
  }

  /** تاريخ راكب واحد + حالته الحالية. */
  @Get('rider/:riderId')
  async rider(@Param('riderId') riderId: string) {
    const [records, state] = await Promise.all([
      this.noShows.history(riderId),
      this.noShows.blockStateFor(riderId),
    ]);
    return {
      policy: this.noShows.policy,
      blocked: state.blocked,
      noShowCount: state.countInWindow,
      blockedUntil: state.blockedUntil?.toISOString() ?? null,
      records,
    };
  }

  /** ألغِ واقعة واحدة. */
  @Post(':id/void')
  @HttpCode(HttpStatus.OK)
  voidOne(
    @CurrentUser('id') adminId: string,
    @Param('id') id: string,
    @Body() dto: VoidNoShowDto,
  ) {
    return this.noShows.void(id, adminId, dto.reason);
  }

  /** ارفع الإيقاف: تُلغى كل الوقائع السارية داخل النافذة. */
  @Post('rider/:riderId/lift')
  @HttpCode(HttpStatus.OK)
  lift(
    @CurrentUser('id') adminId: string,
    @Param('riderId') riderId: string,
    @Body() dto: VoidNoShowDto,
  ) {
    return this.noShows.liftBlock(riderId, adminId, dto.reason);
  }
}
