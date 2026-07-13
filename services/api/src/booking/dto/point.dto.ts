import { IsNumber, IsNotEmpty, IsString, Max, MaxLength, Min } from 'class-validator';

/** A door-to-door pickup/dropoff point marked by the rider on the map. */
export class PointDto {
  @IsNumber({}, { message: 'خط العرض غير صالح.' })
  @Min(-90, { message: 'خط العرض خارج النطاق.' })
  @Max(90, { message: 'خط العرض خارج النطاق.' })
  lat!: number;

  @IsNumber({}, { message: 'خط الطول غير صالح.' })
  @Min(-180, { message: 'خط الطول خارج النطاق.' })
  @Max(180, { message: 'خط الطول خارج النطاق.' })
  lng!: number;

  @IsString()
  @IsNotEmpty({ message: 'اسم الموقع مطلوب.' })
  @MaxLength(200)
  label!: string;
}
