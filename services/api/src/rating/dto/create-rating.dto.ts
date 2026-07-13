import { IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class CreateRatingDto {
  @IsString()
  @IsNotEmpty({ message: 'الرحلة مطلوبة.' })
  tripId!: string;

  @IsString()
  @IsNotEmpty({ message: 'المستخدم المُقيَّم مطلوب.' })
  toUserId!: string;

  @IsInt({ message: 'التقييم يجب أن يكون رقماً.' })
  @Min(1, { message: 'التقييم من 1 إلى 5.' })
  @Max(5, { message: 'التقييم من 1 إلى 5.' })
  score!: number;

  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'التعليق طويل جداً.' })
  comment?: string;
}
