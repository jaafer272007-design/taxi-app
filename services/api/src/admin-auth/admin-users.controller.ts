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
import { AdminUsersService } from './admin-users.service';
import { CurrentAdmin } from './decorators/current-admin.decorator';
import { CreateAdminDto } from './dto/create-admin.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { UpdateAdminDto } from './dto/update-admin.dto';
import { SuperAdminGuard } from './guards/super-admin.guard';
import type { AdminPrincipal } from '../auth/admin-principal';

/**
 * Admin account management. The whole controller is SUPER_ADMIN-only — a normal
 * ADMIN gets 403 on every route here, including a direct URL hit, because the
 * guard is on the class rather than on individual handlers.
 */
@Controller('admin/users')
@UseGuards(JwtAuthGuard, SuperAdminGuard)
export class AdminUsersController {
  constructor(private readonly admins: AdminUsersService) {}

  @Get()
  list() {
    return this.admins.list();
  }

  @Post()
  create(@Body() dto: CreateAdminDto, @CurrentAdmin() actor: AdminPrincipal) {
    return this.admins.create(dto, actor.id);
  }

  @Patch(':id')
  setActive(
    @Param('id') id: string,
    @Body() dto: UpdateAdminDto,
    @CurrentAdmin() actor: AdminPrincipal,
  ) {
    return this.admins.setActive(id, dto.active, actor.id);
  }

  @Post(':id/password')
  @HttpCode(HttpStatus.OK)
  resetPassword(@Param('id') id: string, @Body() dto: ResetPasswordDto) {
    return this.admins.resetPassword(id, dto.password);
  }
}
