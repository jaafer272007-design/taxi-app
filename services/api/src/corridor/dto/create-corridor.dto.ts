import { IsInt, IsNotEmpty, IsString, Min } from 'class-validator';

export class CreateCorridorDto {
  @IsString()
  @IsNotEmpty({ message: 'مدينة الانطلاق مطلوبة.' })
  originCity!: string;

  @IsString()
  @IsNotEmpty({ message: 'مدينة الوصول مطلوبة.' })
  destCity!: string;

  // IQD, integer (no fractions).
  @IsInt({ message: 'السعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر يجب أن يكون أكبر من صفر.' })
  pricePerSeat!: number;
}
