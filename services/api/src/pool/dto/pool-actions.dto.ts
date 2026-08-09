import { IsBoolean, IsInt, IsISO8601, IsOptional, Min } from 'class-validator';

/**
 * استلام تجمّع.
 *
 * `departureTime` اختياري: الافتراضي بداية نافذة التجمّع — أبكر وقت يناسب كل
 * الأعضاء. السائق قد يفضّل وقتاً أمتع داخل النافذة، وأي وقت داخلها مقبول من
 * الجميع بالتعريف (النافذة تقاطعُ نوافذهم). الخدمة تتحقّق من أنه داخلها.
 */
export class ClaimPoolDto {
  @IsOptional()
  @IsISO8601({}, { message: 'وقت المغادرة غير صالح.' })
  departureTime?: string;
}

/** اقتراح رفع السعر — القيمة الجديدة فقط؛ كل الحدود تُفرض في الخدمة. */
export class ProposeRaiseDto {
  @IsInt({ message: 'السعر يجب أن يكون رقماً صحيحاً (IQD).' })
  @Min(1, { message: 'السعر يجب أن يكون أكبر من صفر.' })
  newPricePerSeat!: number;
}

/**
 * ردّ الراكب على الرفع.
 *
 * `accept` صريح لا مسارَين منفصلَين (`/accept` و`/decline`): الرفض فعل من
 * الدرجة الأولى هنا، لا غياب فعل — الراكب الذي يرفض يُطلق فوراً بلا عقوبة،
 * ومسار واحد يجعل ذلك ظاهراً في التوقيع نفسه.
 */
export class RespondToRaiseDto {
  @IsBoolean({ message: 'الردّ يجب أن يكون قبولاً أو رفضاً.' })
  accept!: boolean;
}
