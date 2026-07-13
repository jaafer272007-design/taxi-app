import { IsInt, IsNotEmpty, IsString, Max, Min } from 'class-validator';

export class CreateVehicleDto {
  @IsString()
  @IsNotEmpty({ message: 'نوع السيارة مطلوب.' })
  make!: string;

  @IsString()
  @IsNotEmpty({ message: 'موديل السيارة مطلوب.' })
  model!: string;

  @IsString()
  @IsNotEmpty({ message: 'رقم اللوحة مطلوب.' })
  plate!: string;

  @IsString()
  @IsNotEmpty({ message: 'لون السيارة مطلوب.' })
  color!: string;

  // Max vehicle capacity. A trip's seats are additionally capped at 4 (see brief §9).
  @IsInt({ message: 'عدد المقاعد يجب أن يكون رقماً.' })
  @Min(1, { message: 'عدد المقاعد يجب أن يكون 1 على الأقل.' })
  @Max(50, { message: 'عدد المقاعد غير منطقي.' })
  seats!: number;
}
