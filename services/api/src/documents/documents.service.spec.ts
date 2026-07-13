import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { DocumentsService } from './documents.service';
import { PrismaService } from '../prisma/prisma.service';

describe('DocumentsService.authorizeAccess', () => {
  let prisma: { document: { findUnique: jest.Mock } };
  let service: DocumentsService;

  beforeEach(() => {
    prisma = { document: { findUnique: jest.fn() } };
    service = new DocumentsService(prisma as unknown as PrismaService);
  });

  it('allows the owning driver', async () => {
    prisma.document.findUnique.mockResolvedValue({ id: 'doc1', url: '/u/x', driver: { userId: 'owner' } });
    await expect(
      service.authorizeAccess('doc1', { id: 'owner', roles: [UserRole.RIDER, UserRole.DRIVER] }),
    ).resolves.toMatchObject({ id: 'doc1' });
  });

  it('allows an ADMIN who is not the owner', async () => {
    prisma.document.findUnique.mockResolvedValue({ id: 'doc1', url: '/u/x', driver: { userId: 'someone-else' } });
    await expect(
      service.authorizeAccess('doc1', { id: 'admin', roles: [UserRole.ADMIN] }),
    ).resolves.toMatchObject({ id: 'doc1' });
  });

  it('forbids a non-owner non-admin (403)', async () => {
    prisma.document.findUnique.mockResolvedValue({ id: 'doc1', url: '/u/x', driver: { userId: 'owner' } });
    await expect(
      service.authorizeAccess('doc1', { id: 'intruder', roles: [UserRole.RIDER] }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('404s a missing document', async () => {
    prisma.document.findUnique.mockResolvedValue(null);
    await expect(
      service.authorizeAccess('missing', { id: 'admin', roles: [UserRole.ADMIN] }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
