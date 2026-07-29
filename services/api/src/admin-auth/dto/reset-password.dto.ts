import { IsString, MaxLength, MinLength } from 'class-validator';
import { PasswordService } from '../password.service';

export class ResetPasswordDto {
  @IsString({ message: 'كلمة المرور مطلوبة.' })
  @MinLength(PasswordService.MIN_LENGTH, {
    message: `كلمة المرور يجب أن تكون ${PasswordService.MIN_LENGTH} أحرف على الأقل.`,
  })
  @MaxLength(200, { message: 'كلمة المرور طويلة جداً.' })
  password!: string;
}
