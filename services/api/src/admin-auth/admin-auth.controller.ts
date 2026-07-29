import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { AdminAuthService } from './admin-auth.service';
import { CurrentAdmin } from './decorators/current-admin.decorator';
import { AdminLoginDto } from './dto/admin-login.dto';
import type { AdminPrincipal } from '../auth/admin-principal';

@Controller('admin/auth')
export class AdminAuthController {
  constructor(private readonly auth: AdminAuthService) {}

  /**
   * Username + password → admin JWT. Deliberately NOT the OTP flow: admins are
   * a small internal group and WhatsApp credentials are still pending.
   *
   * `@HttpCode(OK)` because a login is not a resource creation.
   */
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: AdminLoginDto, @Req() req: Request) {
    return this.auth.login(dto.username, dto.password, clientIp(req));
  }

  /**
   * Who am I? The admin app calls this on every server render to decide
   * whether to show the admin-management nav item — the answer must come from
   * the backend, never from a client-decoded JWT.
   */
  @Get('me')
  @UseGuards(JwtAuthGuard)
  me(@CurrentAdmin() admin: AdminPrincipal | null) {
    // A rider/driver token authenticates fine but is not an admin session.
    if (!admin) {
      throw new UnauthorizedException();
    }
    return {
      id: admin.id,
      username: admin.username,
      role: admin.adminRole,
    };
  }
}

/**
 * Best-effort client IP for the login throttle.
 *
 * `X-Forwarded-For` is attacker-controlled unless a trusted proxy rewrites it,
 * so this is a rate-limiting *hint*, not an authorisation input — the worst a
 * forged header achieves is dodging the throttle, which the per-username half
 * of the key still constrains. Behind a real proxy, enable Express's
 * `trust proxy` so `req.ip` is the resolved client address.
 */
function clientIp(req: Request): string {
  return req.ip ?? req.socket?.remoteAddress ?? 'unknown';
}
