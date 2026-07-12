import {
  Injectable,
  UnauthorizedException,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomInt } from 'crypto';
import { RedisService } from '../redis/redis.service';

/**
 * OTP lifecycle in Redis:
 *   otp:code:{phone}     the active code (TTL = OTP_TTL_SECONDS)
 *   otp:attempts:{phone} wrong-code counter (expires with the code)
 *   otp:rate:{phone}     request-otp counter (TTL = rate-limit window)
 */
@Injectable()
export class OtpService {
  private readonly ttlSeconds: number;
  private readonly length: number;
  private readonly rateMax: number;
  private readonly rateWindow: number;
  private readonly maxVerifyAttempts: number;

  constructor(
    private readonly redis: RedisService,
    config: ConfigService,
  ) {
    this.ttlSeconds = Number(config.get('OTP_TTL_SECONDS')) || 300;
    this.length = Number(config.get('OTP_LENGTH')) || 6;
    this.rateMax = Number(config.get('OTP_RATE_LIMIT_MAX')) || 3;
    this.rateWindow = Number(config.get('OTP_RATE_LIMIT_WINDOW_SECONDS')) || 600;
    this.maxVerifyAttempts = Number(config.get('OTP_MAX_VERIFY_ATTEMPTS')) || 5;
  }

  private codeKey(phone: string): string {
    return `otp:code:${phone}`;
  }
  private attemptsKey(phone: string): string {
    return `otp:attempts:${phone}`;
  }
  private rateKey(phone: string): string {
    return `otp:rate:${phone}`;
  }

  /** Cryptographically-random numeric code, zero-padded to `length`. */
  private generateCode(): string {
    let code = '';
    for (let i = 0; i < this.length; i++) {
      code += randomInt(0, 10).toString();
    }
    return code;
  }

  /**
   * Rate-limit, generate, and store a fresh OTP. Returns the plaintext code
   * so the caller can deliver it (WhatsApp, or the dev console fallback).
   * Throws 429 when the per-phone request budget is exhausted.
   */
  async requestOtp(phone: string): Promise<string> {
    const count = await this.redis.incrWithWindow(this.rateKey(phone), this.rateWindow);
    if (count > this.rateMax) {
      throw new HttpException(
        'لقد طلبت رموزاً كثيرة. انتظر قليلاً قبل المحاولة مرة أخرى.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const code = this.generateCode();
    await this.redis.setEx(this.codeKey(phone), code, this.ttlSeconds);
    await this.redis.del(this.attemptsKey(phone));
    return code;
  }

  /**
   * Verify a submitted code. Consumes the code on success. Enforces a cap on
   * wrong attempts so a code can't be brute-forced within its TTL.
   */
  async verifyOtp(phone: string, code: string): Promise<void> {
    const stored = await this.redis.get(this.codeKey(phone));
    if (!stored) {
      throw new UnauthorizedException('انتهت صلاحية الرمز أو لم يُطلب. اطلب رمزاً جديداً.');
    }

    const attempts = await this.redis.incrWithWindow(this.attemptsKey(phone), this.ttlSeconds);
    if (attempts > this.maxVerifyAttempts) {
      await this.redis.del(this.codeKey(phone), this.attemptsKey(phone));
      throw new UnauthorizedException('عدد المحاولات كثير. اطلب رمزاً جديداً.');
    }

    if (stored !== code) {
      throw new UnauthorizedException('رمز التحقق غير صحيح.');
    }

    // Success — burn the code so it can't be reused.
    await this.redis.del(this.codeKey(phone), this.attemptsKey(phone));
  }
}
