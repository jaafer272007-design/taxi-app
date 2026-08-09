import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * سبب أي تدخّل إداري.
 *
 * **مطلوب على كل فعل بلا استثناء.** الفعل يغيّر رحلة شخص أو دخل سائق، وقد
 * يُراجَع بعد أسابيع. سبب مكتوب لحظة الفعل هو الشيء الوحيد الذي سيبقى؛ ذاكرة
 * مَن نفّذه لن تبقى.
 *
 * الحد الأدنى ٣ أحرف حتى لا يمرّ «.» أو «ok» كسبب. نفس شرط
 * [VoidNoShowDto] عمداً — قاعدة واحدة لكل ما يُسجَّل بالسجل.
 */
export class InterveneDto {
  @IsString()
  @IsNotEmpty({ message: 'السبب مطلوب.' })
  @MinLength(3, { message: 'اكتب سبباً واضحاً (٣ أحرف على الأقل).' })
  @MaxLength(500, { message: 'السبب طويل جداً.' })
  reason!: string;
}
