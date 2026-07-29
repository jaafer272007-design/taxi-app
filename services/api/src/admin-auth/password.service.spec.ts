import { BadRequestException } from '@nestjs/common';
import { PasswordService } from './password.service';

describe('PasswordService', () => {
  const service = new PasswordService();

  it('produces a bcrypt hash, never the plaintext', async () => {
    const hash = await service.hash('correct-horse-battery');

    expect(hash).not.toContain('correct-horse-battery');
    // $2a/$2b/$2y = bcrypt, followed by the cost factor.
    expect(hash).toMatch(/^\$2[aby]\$\d{2}\$/);
    expect(hash).toContain(`$${PasswordService.COST}$`);
  });

  it('salts, so the same password hashes differently every time', async () => {
    const [a, b] = await Promise.all([service.hash('same-password'), service.hash('same-password')]);

    expect(a).not.toBe(b);
    // …and both still verify.
    await expect(service.verify('same-password', a)).resolves.toBe(true);
    await expect(service.verify('same-password', b)).resolves.toBe(true);
  });

  it('verifies the right password and rejects the wrong one', async () => {
    const hash = await service.hash('correct-horse-battery');

    await expect(service.verify('correct-horse-battery', hash)).resolves.toBe(true);
    await expect(service.verify('Correct-horse-battery', hash)).resolves.toBe(false);
    await expect(service.verify('', hash)).resolves.toBe(false);
  });

  it('enforces the minimum length', () => {
    expect(() => service.assertStrongEnough('short')).toThrow(BadRequestException);
    expect(() => service.assertStrongEnough('x'.repeat(PasswordService.MIN_LENGTH - 1))).toThrow(
      BadRequestException,
    );
    expect(() => service.assertStrongEnough('x'.repeat(PasswordService.MIN_LENGTH))).not.toThrow();
  });

  it('never puts the password in the rejection message', () => {
    try {
      service.assertStrongEnough('hunter2');
      fail('expected a BadRequestException');
    } catch (err) {
      expect((err as Error).message).not.toContain('hunter2');
    }
  });

  it('verifyDecoy always reports failure', async () => {
    await expect(service.verifyDecoy('anything')).resolves.toBe(false);
    await expect(service.verifyDecoy('bcrypt-timing-decoy')).resolves.toBe(false);
  });
});
