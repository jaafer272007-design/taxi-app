import { Injectable, BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Gender, Prisma, User, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from './otp.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { normalizeIraqiPhone } from '../common/phone.util';
import { UpdateMeDto } from './dto/update-me.dto';

/**
 * The rider's own emergency contact.
 *
 * Name AND phone, never one without the other — a bare number on a screen
 * opened under stress is not something anyone can act on with confidence.
 */
export interface EmergencyContact {
  name: string;
  phone: string;
}

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

  /**
   * `null` for almost everyone, and that is the designed default — the feature
   * is opt-in and the app must show nothing at all until it is set.
   *
   * **This field is the reason `PublicUser` is not safe to hand to anyone but
   * its owner.** It appears in exactly one response, `GET /auth/me`, which is
   * self-only by construction (the id comes from the JWT, never from a param).
   * Nothing else in the server may serialise it — see
   * `emergency-contact.int-spec.ts`, which asserts that against the real
   * driver-facing payloads rather than trusting this comment.
   */
  emergencyContact: EmergencyContact | null;
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
      // Both columns or neither. `updateMe` writes them as a pair, but a row
      // half-written by a migration or by hand must not produce a contact the
      // app would render and then fail to dial.
      emergencyContact:
        user.emergencyContactName && user.emergencyContactPhone
          ? { name: user.emergencyContactName, phone: user.emergencyContactPhone }
          : null,
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
    // Three distinct cases: absent = leave alone, null = clear, object = set.
    // Written as a PAIR in every branch, so the "name but no number" row that
    // toPublicUser has to defend against can never originate here.
    if (dto.emergencyContact !== undefined) {
      if (dto.emergencyContact === null) {
        data.emergencyContactName = null;
        data.emergencyContactPhone = null;
      } else {
        const phone = normalizeIraqiPhone(dto.emergencyContact.phone);
        if (!phone) {
          throw new BadRequestException(
            'رقم جهة الاتصال غير صالح. استخدم رقم موبايل عراقي (+964).',
          );
        }
        const name = dto.emergencyContact.name.trim();
        if (!name) {
          throw new BadRequestException('اسم جهة الاتصال مطلوب.');
        }
        // A rider's own number as their emergency contact is a silent
        // no-op in the moment it is needed — the phone would dial itself.
        if (phone === (await this.phoneOf(userId))) {
          throw new BadRequestException('اختر رقماً غير رقمك.');
        }
        data.emergencyContactName = name;
        data.emergencyContactPhone = phone;
      }
    }
    const user = await this.prisma.user.update({ where: { id: userId }, data });
    return this.toPublicUser(user);
  }

  /** The caller's own number, for the "don't save your own number" guard. */
  private async phoneOf(userId: string): Promise<string | null> {
    const row = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { phone: true },
    });
    return row?.phone ?? null;
  }
}
