import { IsBoolean } from 'class-validator';

export class UpdateAdminDto {
  @IsBoolean({ message: 'قيمة التفعيل غير صالحة.' })
  active!: boolean;
}
