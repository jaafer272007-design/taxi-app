import { Injectable, BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { User, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from './otp.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { normalizeIraqiPhone } from '../common/phone.util';

export interface PublicUser {
  id: string;
  phone: string;
  name: string | null;
  roles: UserRole[];
  createdAt: Date;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly otp: OtpService,
    private readonly whatsapp: WhatsappService,
    private readonly jwt: JwtService,
  ) {}

  private requireIraqiPhone(rawPhone: string): string {
    const phone = normalizeIraqiPhone(rawPhone);
    if (!phone) {
      throw new BadRequestException('رقم الهاتف غير صالح. استخدم رقم موبايل عراقي (+964).');
    }
    return phone;
  }

  private toPublicUser(user: User): PublicUser {
    return {
      id: user.id,
      phone: user.phone,
      name: user.name,
      roles: user.roles,
      createdAt: user.createdAt,
    };
  }

  /** Step 1 — generate + deliver an OTP. Never returns the code. */
  async requestOtp(rawPhone: string): Promise<{ message: string }> {
    const phone = this.requireIraqiPhone(rawPhone);
    const code = await this.otp.requestOtp(phone);
    await this.whatsapp.sendOtp(phone, code);
    return { message: 'تم إرسال رمز التحقق عبر واتساب.' };
  }

  /** Step 2 — verify the OTP, upsert the user (default role RIDER), issue a JWT. */
  async verifyOtp(rawPhone: string, code: string): Promise<{ accessToken: string; user: PublicUser }> {
    const phone = this.requireIraqiPhone(rawPhone);
    await this.otp.verifyOtp(phone, code);

    let user = await this.prisma.user.findUnique({ where: { phone } });
    if (!user) {
      user = await this.prisma.user.create({
        data: { phone, roles: [UserRole.RIDER] },
      });
    }

    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      phone: user.phone,
      roles: user.roles,
    });

    return { accessToken, user: this.toPublicUser(user) };
  }

  /** GET /auth/me — the authenticated user. */
  async me(userId: string): Promise<PublicUser> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new UnauthorizedException();
    }
    return this.toPublicUser(user);
  }
}
