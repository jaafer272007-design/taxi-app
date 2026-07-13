import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { NotificationService } from './notification.service';
import { RegisterDeviceDto } from './dto/register-device.dto';

@Controller('devices')
@UseGuards(JwtAuthGuard)
export class DevicesController {
  constructor(private readonly notifications: NotificationService) {}

  @Post()
  register(@CurrentUser('id') userId: string, @Body() dto: RegisterDeviceDto) {
    return this.notifications.registerDevice(userId, dto);
  }

  @Delete(':token')
  @HttpCode(HttpStatus.OK)
  remove(@CurrentUser('id') userId: string, @Param('token') token: string) {
    return this.notifications.removeDevice(userId, token);
  }
}
