import { BadRequestException, Injectable } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';

/**
 * The one place a plaintext admin password is ever handled.
 *
 * `bcryptjs` rather than the native `bcrypt`/`argon2` bindings: it is the same
 * algorithm at the same cost, but pure JS, so `npm ci` needs no toolchain and
 * CI cannot fail on a node-gyp rebuild. Admin login is a low-traffic path
 * behind a rate limiter, so the throughput difference is irrelevant here.
 */
@Injectable()
export class PasswordService {
  /**
   * bcrypt work factor. 12 is ~250ms on commodity hardware in 2026 — slow
   * enough to make offline cracking expensive, fast enough for an interactive
   * login. Raising it is safe: existing hashes carry their own cost parameter
   * and keep verifying.
   */
  static readonly COST = 12;

  /** Minimum admin password length. */
  static readonly MIN_LENGTH = 10;

  /**
   * A dummy hash verified against when the username does not exist, so a
   * missing account costs the same wall-clock time as a wrong password. Without
   * it, "instant 401" vs "250ms 401" leaks which usernames are real.
   */
  private readonly decoyHash = bcrypt.hashSync('bcrypt-timing-decoy', PasswordService.COST);

  /**
   * Validates the password policy. Throws 400 with an Arabic message — the
   * password itself is never echoed back.
   */
  assertStrongEnough(password: string): void {
    if (typeof password !== 'string' || password.length < PasswordService.MIN_LENGTH) {
      throw new BadRequestException(
        `كلمة المرور يجب أن تكون ${PasswordService.MIN_LENGTH} أحرف على الأقل.`,
      );
    }
    if (password.trim().length === 0) {
      throw new BadRequestException('كلمة المرور غير صالحة.');
    }
  }

  hash(password: string): Promise<string> {
    return bcrypt.hash(password, PasswordService.COST);
  }

  verify(password: string, hash: string): Promise<boolean> {
    return bcrypt.compare(password, hash);
  }

  /**
   * Burn the same time a real verification would, then report failure. Call
   * this on the "no such username" branch of login.
   */
  async verifyDecoy(password: string): Promise<false> {
    await bcrypt.compare(password, this.decoyHash);
    return false;
  }
}
