import { IsInt, IsNotEmpty, IsString, Max, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { PointDto } from './point.dto';

export class CreateBookingDto {
  @IsString()
  @IsNotEmpty({ message: 'الرحلة مطلوبة.' })
  tripId!: string;

  @ValidateNested()
  @Type(() => PointDto)
  pickup!: PointDto;

  @ValidateNested()
  @Type(() => PointDto)
  dropoff!: PointDto;

  @IsInt({ message: 'عدد المقاعد يجب أن يكون رقماً.' })
  @Min(1, { message: 'مقعد واحد على الأقل.' })
  @Max(4, { message: '4 مقاعد كحد أقصى للحجز.' })
  seatCount!: number;
}
