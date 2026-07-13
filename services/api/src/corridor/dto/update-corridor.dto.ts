import { IsBoolean, IsInt, IsNotEmpty, IsOptional, IsString, Min } from 'class-validator';

export class UpdateCorridorDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty({ message: 'مدينة الانطلاق لا يمكن أن تكون فارغة.' })
  originCity?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty({ message: 'مدينة الوصول لا يمكن أن تكون فارغة.' })
  destCity?: string;

  @IsOptional()
  @IsInt({ message: 'السعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر يجب أن يكون أكبر من صفر.' })
  pricePerSeat?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
