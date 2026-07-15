import { Transform } from 'class-transformer';
import {
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Gender } from '@prisma/client';

/// Partial profile update. Either field may be sent alone (e.g. set the name in
/// onboarding, then the gender), but a profile is "complete" only once BOTH name
/// and gender are set (see AuthService.toPublicUser → profileComplete).
export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsNotEmpty({ message: 'الاسم مطلوب.' })
  @MinLength(2, { message: 'الاسم قصير جداً.' })
  @MaxLength(80, { message: 'الاسم طويل جداً.' })
  name?: string;

  @IsOptional()
  @IsEnum(Gender, { message: 'الجنس غير صالح.' })
  gender?: Gender;
}
