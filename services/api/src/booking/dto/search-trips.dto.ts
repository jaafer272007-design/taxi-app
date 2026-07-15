import { IsEnum, IsISO8601, IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { Gender, TripType } from '@prisma/client';

export class SearchTripsDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  corridorId?: string;

  // Filter by trip audience (عامة / نسائية-عائلية).
  @IsOptional()
  @IsEnum(TripType, { message: 'نوع الرحلة غير صالح.' })
  tripType?: TripType;

  // Filter by the driver's gender. Near-zero female-driver supply for now — an
  // empty result is a valid outcome, not an error.
  @IsOptional()
  @IsEnum(Gender, { message: 'الجنس غير صالح.' })
  driverGender?: Gender;

  // A calendar day (YYYY-MM-DD or full ISO); interpreted in the process TZ
  // (Asia/Baghdad). Filters trips departing that day.
  @IsOptional()
  @IsISO8601({ strict: false }, { message: 'التاريخ غير صالح.' })
  date?: string;

  // Optional ISO datetime bounds on departureTime.
  @IsOptional()
  @IsISO8601({ strict: false }, { message: 'وقت البداية غير صالح.' })
  fromTime?: string;

  @IsOptional()
  @IsISO8601({ strict: false }, { message: 'وقت النهاية غير صالح.' })
  toTime?: string;
}
