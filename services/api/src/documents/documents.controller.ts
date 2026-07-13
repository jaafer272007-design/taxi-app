import { Controller, Get, Param, Res, StreamableFile, UseGuards } from '@nestjs/common';
import { Response } from 'express';
import { User } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { StorageService } from '../storage/storage.service';
import { DocumentsService } from './documents.service';

@Controller('documents')
@UseGuards(JwtAuthGuard)
export class DocumentsController {
  constructor(
    private readonly documents: DocumentsService,
    private readonly storage: StorageService,
  ) {}

  /** Stream a driver document. Owning driver or ADMIN only (enforced in the service). */
  @Get(':id')
  async get(
    @Param('id') id: string,
    @CurrentUser() user: User,
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const doc = await this.documents.authorizeAccess(id, user);
    const { stream, contentType, filename } = this.storage.openReadStream(doc.url);
    res.set({
      'Content-Type': contentType,
      'Content-Disposition': `inline; filename="${filename}"`,
    });
    return new StreamableFile(stream);
  }
}
