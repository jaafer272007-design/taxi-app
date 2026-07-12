import { IsNotEmpty, IsString, Matches } from 'class-validator';

export class VerifyOtpDto {
  @IsString()
  @IsNotEmpty({ message: 'رقم الهاتف مطلوب.' })
  phone!: string;

  @IsString()
  @IsNotEmpty({ message: 'رمز التحقق مطلوب.' })
  @Matches(/^\d{4,8}$/, { message: 'رمز التحقق يجب أن يكون أرقاماً.' })
  code!: string;
}
