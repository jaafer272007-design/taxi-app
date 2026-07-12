import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { promises as fs } from 'fs';
import { extname, join } from 'path';

/**
 * Local-disk file storage for dev. Files land under UPLOAD_DIR and the returned
 * path is saved in Document.url.
 *
 * TODO(prod): swap this for object storage (S3-compatible) before production —
 * keep the same `save()` signature so callers don't change.
 */
@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private readonly uploadDir: string;

  constructor(config: ConfigService) {
    this.uploadDir = config.get<string>('UPLOAD_DIR') || './uploads';
  }

  async save(buffer: Buffer, originalName: string, subdir = ''): Promise<string> {
    const dir = join(this.uploadDir, subdir);
    await fs.mkdir(dir, { recursive: true });

    const ext = extname(originalName).toLowerCase().replace(/[^.a-z0-9]/g, '');
    const filename = `${randomUUID()}${ext}`;
    const fullPath = join(dir, filename);

    await fs.writeFile(fullPath, buffer);
    this.logger.debug(`Stored upload at ${fullPath}`);
    return fullPath;
  }
}
