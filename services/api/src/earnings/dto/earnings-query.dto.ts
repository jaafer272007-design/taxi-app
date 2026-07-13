import { IsIn, IsOptional } from 'class-validator';

export class EarningsQueryDto {
  @IsOptional()
  @IsIn(['today', 'all'], { message: 'النطاق يجب أن يكون today أو all.' })
  range?: 'today' | 'all';
}
