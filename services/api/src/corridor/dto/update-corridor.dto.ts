import { IsBoolean, IsIn, IsInt, IsOptional, Min } from 'class-validator';
import { IRAQI_CITIES } from '../cities';

export class UpdateCorridorDto {
  @IsOptional()
  @IsIn([...IRAQI_CITIES], { message: 'مدينة الانطلاق غير صالحة.' })
  originCity?: string;

  @IsOptional()
  @IsIn([...IRAQI_CITIES], { message: 'مدينة الوصول غير صالحة.' })
  destCity?: string;

  @IsOptional()
  @IsInt({ message: 'السعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر يجب أن يكون أكبر من صفر.' })
  pricePerSeat?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
