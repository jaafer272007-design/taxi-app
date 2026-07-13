import { Transform } from 'class-transformer';
import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

export class UpdateMeDto {
  @IsString()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsNotEmpty({ message: 'الاسم مطلوب.' })
  @MinLength(2, { message: 'الاسم قصير جداً.' })
  @MaxLength(80, { message: 'الاسم طويل جداً.' })
  name!: string;
}
