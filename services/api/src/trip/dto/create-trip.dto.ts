import { IsBoolean, IsInt, IsISO8601, IsNotEmpty, IsOptional, IsString, Min } from 'class-validator';

export class CreateTripDto {
  @IsString()
  @IsNotEmpty({ message: 'الممر مطلوب.' })
  corridorId!: string;

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
