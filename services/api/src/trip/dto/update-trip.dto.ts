import { IsISO8601, IsInt, IsOptional, Min } from 'class-validator';

export class UpdateTripDto {
  @IsOptional()
  @IsISO8601({}, { message: 'وقت المغادرة غير صالح.' })
  departureTime?: string;

  @IsOptional()
  @IsInt({ message: 'عدد المقاعد يجب أن يكون رقماً.' })
  @Min(1, { message: 'عدد المقاعد يجب أن يكون 1 على الأقل.' })
  seatsTotal?: number;
}
