import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Document, User, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class DocumentsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Return the document only if the requester is the owning driver or an ADMIN.
   * Anyone else → 403. Missing document → 404.
   */
  async authorizeAccess(documentId: string, user: Pick<User, 'id' | 'roles'>): Promise<Document> {
    const doc = await this.prisma.document.findUnique({
      where: { id: documentId },
      include: { driver: { select: { userId: true } } },
    });
    if (!doc) {
      throw new NotFoundException('المستند غير موجود.');
    }

    const isAdmin = (user.roles ?? []).includes(UserRole.ADMIN);
    const isOwner = doc.driver.userId === user.id;
    if (!isAdmin && !isOwner) {
      throw new ForbiddenException('لا تملك صلاحية عرض هذا المستند.');
    }
    return doc;
  }
}
