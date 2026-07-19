import { IsIn, IsInt, Min } from 'class-validator';
import { IRAQI_CITIES } from '../cities';

export class CreateCorridorDto {
  @IsIn([...IRAQI_CITIES], { message: 'مدينة الانطلاق غير صالحة.' })
  originCity!: string;

  @IsIn([...IRAQI_CITIES], { message: 'مدينة الوصول غير صالحة.' })
  destCity!: string;

  // IQD, integer (no fractions).
  @IsInt({ message: 'السعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر يجب أن يكون أكبر من صفر.' })
  pricePerSeat!: number;
}
