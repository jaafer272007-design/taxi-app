import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AdminSupportService } from './admin-support.service';
import { AdminAuditService } from './admin-audit.service';
import { InterveneDto } from './dto/intervene.dto';

/**
 * أدوات الدعم.
 *
 * **كل تدخّل يطلب سبباً** (`InterveneDto`, ≥ ٣ أحرف) و**يُسجَّل** بمَن نفّذه.
 * هذا ليس شكليات: قبل هذه الشاشة كان التدخّل الوحيد كتابة SQL — بلا مَن ولا
 * لماذا — والحالة التي يُراجَع فيها القرار لاحقاً هي بالضبط الحالة التي لا
 * يتذكّر فيها أحد شيئاً.
 *
 * **مَن نفّذ يأتي من الـJWT دائماً** (`@CurrentUser`)، ولا يُرسَل من العميل:
 * سجل تدقيق يقبل هوية الفاعل من الطلب هو حقل نصّي، لا سجل.
 */
@Controller('admin/support')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN)
export class AdminSupportController {
  constructor(
    private readonly support: AdminSupportService,
    private readonly audit: AdminAuditService,
  ) {}

  // ── Lookup ──────────────────────────────────────────────────────────────

  @Get('search')
  async search(@Query('q') q = '') {
    const result = await this.support.search(q);
    // A user hit carries their driver profile id when they have one, so the
    // panel can offer both views without a second round trip.
    if (result.kind === 'USER') {
      return {
        ...result,
        driverProfileId: await this.support.driverProfileIdFor(result.user.id),
      };
    }
    return result;
  }

  @Get('riders/:userId')
  rider(@Param('userId') userId: string) {
    return this.support.rider(userId);
  }

  @Get('drivers/:profileId')
  driver(@Param('profileId') profileId: string) {
    return this.support.driver(profileId);
  }

  @Get('trips/:tripId')
  trip(@Param('tripId') tripId: string) {
    return this.support.trip(tripId);
  }

  // ── The audit log ───────────────────────────────────────────────────────

  @Get('actions')
  actions(
    @Query('adminId') adminId?: string,
    @Query('entityType') entityType?: string,
    @Query('entityId') entityId?: string,
  ) {
    return this.audit.list({ adminId, entityType, entityId });
  }

  /** Distinct admins in the log, for the filter control. */
  @Get('actions/admins')
  actionAdmins() {
    return this.audit.actingAdmins();
  }

  // ── Intervention ────────────────────────────────────────────────────────

  @Post('bookings/:id/cancel')
  @HttpCode(HttpStatus.OK)
  cancelBooking(
    @Param('id') id: string,
    @Body() dto: InterveneDto,
    @CurrentUser() admin: { id: string; username: string },
  ) {
    return this.support.cancelBooking(admin, id, dto.reason);
  }

  @Post('trips/:id/cancel')
  @HttpCode(HttpStatus.OK)
  cancelTrip(
    @Param('id') id: string,
    @Body() dto: InterveneDto,
    @CurrentUser() admin: { id: string; username: string },
  ) {
    return this.support.cancelTrip(admin, id, dto.reason);
  }

  @Post('drivers/:profileId/suspend')
  @HttpCode(HttpStatus.OK)
  suspend(
    @Param('profileId') profileId: string,
    @Body() dto: InterveneDto,
    @CurrentUser() admin: { id: string; username: string },
  ) {
    return this.support.suspendDriver(admin, profileId, dto.reason);
  }

  @Post('drivers/:profileId/unsuspend')
  @HttpCode(HttpStatus.OK)
  unsuspend(
    @Param('profileId') profileId: string,
    @Body() dto: InterveneDto,
    @CurrentUser() admin: { id: string; username: string },
  ) {
    return this.support.unsuspendDriver(admin, profileId, dto.reason);
  }

  /**
   * The no-show appeal from the rider's support page.
   *
   * Same service the /no-shows page uses — surfaced here so an admin looking
   * at a rider does not have to navigate away and search for them again.
   */
  @Post('no-shows/:recordId/void')
  @HttpCode(HttpStatus.OK)
  voidNoShow(
    @Param('recordId') recordId: string,
    @Body() dto: InterveneDto,
    @CurrentUser() admin: { id: string; username: string },
  ) {
    return this.support.voidNoShow(admin, recordId, dto.reason);
  }

  @Post('riders/:riderId/lift-block')
  @HttpCode(HttpStatus.OK)
  liftBlock(
    @Param('riderId') riderId: string,
    @Body() dto: InterveneDto,
    @CurrentUser() admin: { id: string; username: string },
  ) {
    return this.support.liftBlock(admin, riderId, dto.reason);
  }
}
