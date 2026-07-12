import { IsEnum, IsOptional } from 'class-validator';
import { DriverStatus } from '@prisma/client';

export class ListDriversDto {
  @IsOptional()
  @IsEnum(DriverStatus, { message: 'حالة السائق غير صالحة.' })
  status?: DriverStatus;
}
