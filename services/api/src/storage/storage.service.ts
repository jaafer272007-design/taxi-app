import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { createReadStream, existsSync, ReadStream } from 'fs';
import { promises as fs } from 'fs';
import { basename, extname, join, resolve, sep } from 'path';

const EXT_MIME: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
};

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

  /**
   * Open a stored file for reading. Validates that the path stays inside
   * UPLOAD_DIR (defence-in-depth against traversal, even though stored paths
   * come from our own DB) and infers a content type from the extension.
   */
  openReadStream(storedPath: string): { stream: ReadStream; contentType: string; filename: string } {
    const root = resolve(this.uploadDir);
    const abs = resolve(storedPath);
    if (abs !== root && !abs.startsWith(root + sep)) {
      throw new NotFoundException('الملف غير موجود.');
    }
    if (!existsSync(abs)) {
      throw new NotFoundException('الملف غير موجود.');
    }
    const contentType = EXT_MIME[extname(abs).toLowerCase()] || 'application/octet-stream';
    return { stream: createReadStream(abs), contentType, filename: basename(abs) };
  }
}
