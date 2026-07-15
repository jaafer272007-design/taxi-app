import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsISO8601,
  IsNotEmpty,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';
import { TripType } from '@prisma/client';

export class CreateTripDto {
  @IsString()
  @IsNotEmpty({ message: 'الممر مطلوب.' })
  corridorId!: string;

  // Trip audience — defaults to GENERAL in the service. A driver of any gender
  // may post a WOMEN_FAMILY trip; passenger eligibility is enforced at booking.
  @IsOptional()
  @IsEnum(TripType, { message: 'نوع الرحلة غير صالح.' })
  tripType?: TripType;

  // Provide EITHER departureTime (scheduled) OR departNow=true. Cross-field
  // validation is done in the service.
  @IsOptional()
  @IsISO8601({}, { message: 'وقت المغادرة غير صالح.' })
  departureTime?: string;

  @IsOptional()
  @IsBoolean({ message: 'قيمة "الآن" غير صالحة.' })
  departNow?: boolean;

  @IsInt({ message: 'عدد المقاعد يجب أن يكون رقماً.' })
  @Min(1, { message: 'عدد المقاعد يجب أن يكون 1 على الأقل.' })
  seatsTotal!: number;
}
