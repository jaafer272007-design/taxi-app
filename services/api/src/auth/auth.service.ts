import { Injectable, BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Gender, Prisma, User, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from './otp.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { normalizeIraqiPhone } from '../common/phone.util';
import { UpdateMeDto } from './dto/update-me.dto';

export interface PublicUser {
  id: string;
  phone: string;
  name: string | null;
  gender: Gender | null;
  roles: UserRole[];
  createdAt: Date;
  // A profile is complete only when BOTH name and gender are set. Existing users
  // (gender = null) read as incomplete until they set it; the apps prompt them.
  profileComplete: boolean;
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
      gender: user.gender,
      roles: user.roles,
      createdAt: user.createdAt,
      profileComplete: user.name !== null && user.gender !== null,
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

  /**
   * PATCH /auth/me — set the authenticated user's name and/or gender. Either may
   * be sent alone; only the provided fields are written (a name-only update never
   * clears an existing gender, and vice-versa). Gender is required to COMPLETE a
   * profile (see toPublicUser.profileComplete), but each field is optional here
   * so onboarding can set them in separate steps.
   */
  async updateMe(userId: string, dto: UpdateMeDto): Promise<PublicUser> {
    const data: Prisma.UserUpdateInput = {};
    if (dto.name !== undefined) {
      const trimmed = dto.name.trim();
      if (!trimmed) {
        throw new BadRequestException('الاسم مطلوب.');
      }
      data.name = trimmed;
    }
    if (dto.gender !== undefined) {
      data.gender = dto.gender;
    }
    const user = await this.prisma.user.update({ where: { id: userId }, data });
    return this.toPublicUser(user);
  }
}
