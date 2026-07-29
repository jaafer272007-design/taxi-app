import { IsString, MaxLength, MinLength } from 'class-validator';

export class AdminLoginDto {
  @IsString({ message: 'اسم المستخدم مطلوب.' })
  @MinLength(1, { message: 'اسم المستخدم مطلوب.' })
  @MaxLength(64, { message: 'اسم المستخدم طويل جداً.' })
  username!: string;

  /**
   * Deliberately NOT length-validated here. The login endpoint must not tell a
   * caller that their guess was "too short to be one of ours" — that is a hint
   * about the password policy of real accounts. The policy is enforced where
   * passwords are SET (create / reset), not where they are checked.
   *
   * The max bound is a denial-of-service guard: bcrypt on a multi-megabyte
   * string is free CPU for an attacker.
   */
  @IsString({ message: 'كلمة المرور مطلوبة.' })
  @MaxLength(200, { message: 'كلمة المرور طويلة جداً.' })
  password!: string;
}
