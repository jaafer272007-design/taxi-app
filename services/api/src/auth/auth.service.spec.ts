import { BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from './otp.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';

describe('AuthService.updateMe', () => {
  function makeService(prisma: unknown): AuthService {
    return new AuthService(
      prisma as PrismaService,
      {} as OtpService,
      {} as WhatsappService,
      {} as JwtService,
    );
  }

  it('trims the name, persists it, and returns the public user', async () => {
    const createdAt = new Date();
    const prisma = {
      user: {
        update: jest.fn().mockResolvedValue({
          id: 'u1',
          phone: '+9647701234567',
          name: 'علي حسن',
          roles: ['RIDER'],
          createdAt,
        }),
      },
    };
    const service = makeService(prisma);

    const result = await service.updateMe('u1', '  علي حسن  ');

    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'u1' },
      data: { name: 'علي حسن' },
    });
    expect(result).toEqual({
      id: 'u1',
      phone: '+9647701234567',
      name: 'علي حسن',
      roles: ['RIDER'],
      createdAt,
    });
  });

  it('rejects a blank name without touching the database', async () => {
    const prisma = { user: { update: jest.fn() } };
    const service = makeService(prisma);

    await expect(service.updateMe('u1', '   ')).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.user.update).not.toHaveBeenCalled();
  });
});
