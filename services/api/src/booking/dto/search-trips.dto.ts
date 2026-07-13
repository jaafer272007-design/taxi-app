import { IsISO8601, IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class SearchTripsDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  corridorId?: string;

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
