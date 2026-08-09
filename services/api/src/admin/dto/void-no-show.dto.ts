import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * سبب إلغاء واقعة عدم حضور أو رفع إيقاف.
 *
 * **مطلوب عمداً.** هذا هو مسار التظلّم؛ قرار يرفع عقوبة بلا سبب مكتوب لا
 * يمكن مراجعته لاحقاً، ولا يعطي السياسة أي إشارة عن أي الحالات كانت خاطئة.
 * حد أدنى ٣ أحرف حتى لا يمرّ «.» كسبب.
 */
export class VoidNoShowDto {
  @IsString()
  @IsNotEmpty({ message: 'السبب مطلوب.' })
  @MinLength(3, { message: 'اكتب سبباً واضحاً (٣ أحرف على الأقل).' })
  @MaxLength(500, { message: 'السبب طويل جداً.' })
  reason!: string;
}
