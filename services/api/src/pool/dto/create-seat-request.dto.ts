import {
  IsInt,
  IsISO8601,
  IsNotEmpty,
  IsString,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { PointDto } from '../../booking/dto/point.dto';

/**
 * «أريد مقعداً على هذا الممر بين هذين الوقتين».
 *
 * نفس شكل نقاط الحجز (`PointDto`) عمداً: عند استلام التجمّع تُنسخ هذه النقاط
 * كما هي إلى `SeatBooking`، فأي اختلاف في الشكل كان سيصبح تحويلاً صامتاً.
 *
 * حدود النافذة تُتحقّق في الخدمة لا هنا: القاعدة تشمل «الأمتع بعد الأبكر»
 * و«ليست في الماضي» و«ليست أوسع من السقف»، وكلها تحتاج الساعة والسياسة —
 * وهما بالضبط ما لا يجب أن يعيش في DTO.
 */
export class CreateSeatRequestDto {
  @IsString()
  @IsNotEmpty({ message: 'الممر مطلوب.' })
  corridorId!: string;

  @IsISO8601({}, { message: 'أبكر وقت مغادرة غير صالح.' })
  windowStart!: string;

  @IsISO8601({}, { message: 'أمتع وقت مغادرة غير صالح.' })
  windowEnd!: string;

  @ValidateNested()
  @Type(() => PointDto)
  pickup!: PointDto;

  @ValidateNested()
  @Type(() => PointDto)
  dropoff!: PointDto;

  // نفس سقف الحجز: أربعة مقاعد. راكب يسافر مع عائلته يطلبها في طلب واحد،
  // تماماً كما يحجزها في حجز واحد.
  @IsInt({ message: 'عدد المقاعد يجب أن يكون رقماً.' })
  @Min(1, { message: 'مقعد واحد على الأقل.' })
  @Max(4, { message: '4 مقاعد كحد أقصى.' })
  seatCount!: number;
}
