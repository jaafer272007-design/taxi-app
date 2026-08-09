import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { CreateRouteRequestDto } from './dto/create-route-request.dto';
import { RouteRequestService } from './route-request.service';

/**
 * جانب الراكب من طلبات المسارات: نقطة واحدة، نقرة واحدة.
 *
 * **٢٠٠ لا ٢٠١، وبلا مسار خطأ للتكرار.** النقرة الثانية تعني ما تعنيه الأولى
 * تماماً، والحالة النهائية واحدة: «طلبك مسجّل». ردّ خطأ على نقرة مكرّرة يقرأ
 * كعطل في التطبيق ويعاقب الراكب على شبكة بطيئة — وهو نفس المنطق المثبّت في
 * CLAUDE.md لـ«409 من `POST /ratings` نجاحٌ متكافئ».
 *
 * `alreadyRequested` موجود للصدق لا للتحكّم: التطبيق يعرض نفس التأكيد في
 * الحالتين.
 */
@Controller('route-requests')
export class RouteRequestController {
  constructor(private readonly routeRequests: RouteRequestService) {}

  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async create(@CurrentUser('id') riderId: string, @Body() dto: CreateRouteRequestDto) {
    const { request, alreadyRequested } = await this.routeRequests.record(riderId, {
      corridorId: dto.corridorId,
      requestedFor: dto.requestedFor ? new Date(dto.requestedFor) : null,
    });

    return {
      id: request.id,
      corridorId: request.corridorId,
      createdAt: request.createdAt.toISOString(),
      alreadyRequested,
      // لا وعد بموعد — لا نملك واحداً. راجع `route-requests` في البريف.
      message: 'سنخبرك عندما تتوفر رحلات على هذا المسار.',
    };
  }
}
