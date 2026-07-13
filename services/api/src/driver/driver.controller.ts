import {
  Body,
  Controller,
  Get,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { DriverService } from './driver.service';
import { CreateVehicleDto } from './dto/create-vehicle.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';

@Controller('driver')
@UseGuards(JwtAuthGuard)
export class DriverController {
  constructor(private readonly driver: DriverService) {}

  @Post('profile')
  createProfile(@CurrentUser('id') userId: string) {
    return this.driver.createProfile(userId);
  }

  @Post('vehicle')
  addVehicle(@CurrentUser('id') userId: string, @Body() dto: CreateVehicleDto) {
    return this.driver.upsertVehicle(userId, dto);
  }

  @Post('documents')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 5 * 1024 * 1024 } }))
  uploadDocument(
    @CurrentUser('id') userId: string,
    @Body() dto: UploadDocumentDto,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.driver.uploadDocument(userId, dto.type, file);
  }

  @Get('profile')
  getProfile(@CurrentUser('id') userId: string) {
    return this.driver.getProfile(userId);
  }
}
