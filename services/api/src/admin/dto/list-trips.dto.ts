import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsISO8601, IsNotEmpty, IsOptional, IsString, Min } from 'class-validator';
import { TripStatus } from '@prisma/client';

export class ListTripsDto {
  @IsOptional()
  @IsEnum(TripStatus, { message: 'حالة الرحلة غير صالحة.' })
  status?: TripStatus;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  corridorId?: string;

  @IsOptional()
  @IsISO8601({ strict: false }, { message: 'التاريخ غير صالح.' })
  date?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  perPage?: number;
}
