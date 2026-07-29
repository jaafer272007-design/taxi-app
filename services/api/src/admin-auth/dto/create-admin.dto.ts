import { IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { PasswordService } from '../password.service';

export class CreateAdminDto {
  @IsString({ message: 'اسم المستخدم مطلوب.' })
  @MinLength(3, { message: 'اسم المستخدم يجب أن يكون 3 أحرف على الأقل.' })
  @MaxLength(64, { message: 'اسم المستخدم طويل جداً.' })
  // Latin letters, digits, dot, dash, underscore. Usernames are typed on a
  // login form with no autocomplete and read aloud when handed over, so
  // ambiguous characters (spaces, Arabic-Indic digits, RTL marks) are refused
  // rather than silently normalised into something the admin can't retype.
  @Matches(/^[a-zA-Z0-9._-]+$/, {
    message: 'اسم المستخدم يقبل الحروف اللاتينية والأرقام والنقطة والشرطة فقط.',
  })
  username!: string;

  @IsString({ message: 'كلمة المرور مطلوبة.' })
  @MinLength(PasswordService.MIN_LENGTH, {
    message: `كلمة المرور يجب أن تكون ${PasswordService.MIN_LENGTH} أحرف على الأقل.`,
  })
  @MaxLength(200, { message: 'كلمة المرور طويلة جداً.' })
  password!: string;
}
