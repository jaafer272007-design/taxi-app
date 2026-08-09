import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { RouteRequestService } from '../corridor/route-request.service';

/**
 * الطلب مقابل العرض — الشاشة التي تقرّر أين نستقطب سائقين.
 *
 * هذه **نقطة الميزة كلها**. جانب الراكب يجمع الإشارة وجانب السائق يستهلكها،
 * لكن القرار — «أي ممرّ من الـ٣٠٦ نشتغل عليه هذا الأسبوع» — يُتّخذ هنا.
 * وقبل هذه الشاشة كان يُتّخذ بالتخمين.
 *
 * `unservedOnly=true` هي القائمة القابلة للتنفيذ: طلب موجود، وعرض معدوم.
 */
@Controller('admin/route-requests')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN)
export class AdminRouteRequestController {
  constructor(private readonly routeRequests: RouteRequestService) {}

  @Get()
  async list(@Query('unservedOnly') unservedOnly?: string) {
    const rows = await this.routeRequests.demand({
      unservedOnly: unservedOnly === 'true',
    });
    return {
      // السياسة مرئية للأدمن: رقمٌ يقرّر ما يظهر هنا لا يجوز أن يبقى مخفياً
      // في متغيّر بيئة — نفس سبب إظهار أرقام عدم الحضور في لوحتها.
      policy: this.routeRequests.policy,
      corridors: rows,
    };
  }
}
