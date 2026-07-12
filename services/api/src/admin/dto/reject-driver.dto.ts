import { IsOptional, IsString, MaxLength } from 'class-validator';

export class RejectDriverDto {
  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'سبب الرفض طويل جداً.' })
  reason?: string;
}
