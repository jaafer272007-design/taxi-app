import { IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class RegisterDeviceDto {
  @IsString()
  @IsNotEmpty({ message: 'رمز الجهاز مطلوب.' })
  @MaxLength(4096)
  token!: string;

  @IsIn(['android', 'ios', 'web'], { message: 'المنصّة غير مدعومة.' })
  platform!: string;
}
