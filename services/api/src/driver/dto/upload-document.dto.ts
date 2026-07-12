import { IsEnum } from 'class-validator';
import { DocType } from '@prisma/client';

export class UploadDocumentDto {
  // Sent as a multipart form field alongside the file.
  @IsEnum(DocType, {
    message: 'نوع المستند غير صالح (NATIONAL_ID | DRIVING_LICENSE | VEHICLE_REG).',
  })
  type!: DocType;
}
