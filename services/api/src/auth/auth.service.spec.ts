import { BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Gender } from '@prisma/client';
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

  it('trims the name, persists it, and reports the profile incomplete until gender is set', async () => {
    const createdAt = new Date();
    const prisma = {
      user: {
        update: jest.fn().mockResolvedValue({
          id: 'u1',
          phone: '+9647701234567',
          name: 'علي حسن',
          gender: null,
          roles: ['RIDER'],
          createdAt,
        }),
      },
    };
    const service = makeService(prisma);

    const result = await service.updateMe('u1', { name: '  علي حسن  ' });

    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'u1' },
      data: { name: 'علي حسن' },
    });
    expect(result).toEqual({
      id: 'u1',
      phone: '+9647701234567',
      name: 'علي حسن',
      gender: null,
      roles: ['RIDER'],
      createdAt,
      profileComplete: false, // gender not set yet
    });
  });

  it('sets gender alone (no name) without clobbering the name', async () => {
    const prisma = {
      user: {
        update: jest.fn().mockResolvedValue({
          id: 'u1',
          phone: '+9647701234567',
          name: 'سارة',
          gender: Gender.FEMALE,
          roles: ['RIDER'],
          createdAt: new Date(),
        }),
      },
    };
    const service = makeService(prisma);

    const result = await service.updateMe('u1', { gender: Gender.FEMALE });

    // Only gender is written — a gender-only PATCH must not touch the name.
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'u1' },
      data: { gender: Gender.FEMALE },
    });
    expect(result.gender).toBe(Gender.FEMALE);
    expect(result.profileComplete).toBe(true); // name + gender both set
  });

  it('rejects a blank name without touching the database', async () => {
    const prisma = { user: { update: jest.fn() } };
    const service = makeService(prisma);

    await expect(
      service.updateMe('u1', { name: '   ' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });
});
