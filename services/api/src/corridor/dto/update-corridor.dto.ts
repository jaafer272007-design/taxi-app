import { IsBoolean, IsIn, IsInt, IsOptional, Min } from 'class-validator';
import { IRAQI_CITIES } from '../cities';

/**
 * Every field is optional (partial update), but the three prices are validated
 * TOGETHER against the stored row in CorridorService — raising `minPricePerSeat`
 * alone can still break `min <= suggested <= max`.
 */
export class UpdateCorridorDto {
  @IsOptional()
  @IsIn([...IRAQI_CITIES], { message: 'مدينة الانطلاق غير صالحة.' })
  originCity?: string;

  @IsOptional()
  @IsIn([...IRAQI_CITIES], { message: 'مدينة الوصول غير صالحة.' })
  destCity?: string;

  @IsOptional()
  @IsInt({ message: 'السعر المقترح يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر المقترح يجب أن يكون أكبر من صفر.' })
  suggestedPricePerSeat?: number;

  @IsOptional()
  @IsInt({ message: 'أدنى سعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'أدنى سعر يجب أن يكون أكبر من صفر.' })
  minPricePerSeat?: number;

  @IsOptional()
  @IsInt({ message: 'أعلى سعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'أعلى سعر يجب أن يكون أكبر من صفر.' })
  maxPricePerSeat?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
