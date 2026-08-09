import { Transform, Type } from 'class-transformer';
import {
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { Gender } from '@prisma/client';

/**
 * جهة اتصال للطوارئ — اسم **و** رقم معاً.
 *
 * الحقلان مطلوبان داخل الكائن عمداً: «اسم بلا رقم» لا يمكن الاتصال به،
 * و«رقم بلا اسم» شاشة تُفتح تحت ضغط وفيها رقم مجرّد. المسح يتم بإرسال
 * `emergencyContact: null` — لا بإفراغ حقل منهما.
 */
export class EmergencyContactDto {
  @IsString()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsNotEmpty({ message: 'اسم جهة الاتصال مطلوب.' })
  @MaxLength(80, { message: 'الاسم طويل جداً.' })
  name!: string;

  // الشكل الدقيق يُفحص بالخدمة عبر normalizeIraqiPhone — نفس مصدر الحقيقة
  // الذي يفحص رقم الدخول، فلا تتفرّع قاعدتان لرقم عراقي واحد.
  @IsString()
  @IsNotEmpty({ message: 'رقم جهة الاتصال مطلوب.' })
  phone!: string;
}

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

  /**
   * `undefined` (غائب) = لا تغيير. `null` = امسحها. كائن = اضبطها.
   *
   * الثلاثة حالات مختلفة، ولهذا الحقل كائن لا حقلين مسطّحين: بحقلين منفصلين
   * ما في طريقة تقول «امسح» تختلف عن «لا تغيّر» بلا قيمة سحرية.
   * `@IsOptional` بـ class-validator يمرّر `null` بلا فحص، وهو بالضبط
   * ما نريده هنا.
   */
  @IsOptional()
  @ValidateNested()
  @Type(() => EmergencyContactDto)
  emergencyContact?: EmergencyContactDto | null;
}
