import { IsIn, IsInt, Min } from 'class-validator';
import { IRAQI_CITIES } from '../cities';

/**
 * The admin no longer sets THE price — the driver does. The admin sets the
 * suggestion the driver sees prefilled, plus the band the driver's price must
 * fall inside. The ordering rule (min <= suggested <= max) is cross-field, so it
 * lives in CorridorService where it can name the offending value in Arabic.
 */
export class CreateCorridorDto {
  @IsIn([...IRAQI_CITIES], { message: 'مدينة الانطلاق غير صالحة.' })
  originCity!: string;

  @IsIn([...IRAQI_CITIES], { message: 'مدينة الوصول غير صالحة.' })
  destCity!: string;

  // All three are IQD integers (no fractions).
  @IsInt({ message: 'السعر المقترح يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر المقترح يجب أن يكون أكبر من صفر.' })
  suggestedPricePerSeat!: number;

  @IsInt({ message: 'أدنى سعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'أدنى سعر يجب أن يكون أكبر من صفر.' })
  minPricePerSeat!: number;

  @IsInt({ message: 'أعلى سعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'أعلى سعر يجب أن يكون أكبر من صفر.' })
  maxPricePerSeat!: number;
}
