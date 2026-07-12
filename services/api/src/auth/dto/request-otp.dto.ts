import { IsNotEmpty, IsString } from 'class-validator';

export class RequestOtpDto {
  // Detailed +964 validation happens in AuthService via normalizeIraqiPhone;
  // here we only guarantee a non-empty string reached the controller.
  @IsString()
  @IsNotEmpty({ message: 'رقم الهاتف مطلوب.' })
  phone!: string;
}
