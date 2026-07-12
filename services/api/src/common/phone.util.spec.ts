import { normalizeIraqiPhone, isValidIraqiPhone } from './phone.util';

describe('normalizeIraqiPhone', () => {
  it('normalizes the various ways an Iraqi mobile is typed to E.164', () => {
    const expected = '+9647701234567';
    expect(normalizeIraqiPhone('+9647701234567')).toBe(expected);
    expect(normalizeIraqiPhone('009647701234567')).toBe(expected);
    expect(normalizeIraqiPhone('9647701234567')).toBe(expected);
    expect(normalizeIraqiPhone('07701234567')).toBe(expected);
    expect(normalizeIraqiPhone('7701234567')).toBe(expected);
    expect(normalizeIraqiPhone('+964 770 123 4567')).toBe(expected);
    expect(normalizeIraqiPhone('+964-770-123-4567')).toBe(expected);
  });

  it('accepts the real Iraqi mobile prefixes (75/77/78/79)', () => {
    expect(isValidIraqiPhone('07512345678')).toBe(true);
    expect(isValidIraqiPhone('07812345678')).toBe(true);
    expect(isValidIraqiPhone('07912345678')).toBe(true);
  });

  it('rejects non-Iraqi and malformed numbers', () => {
    expect(normalizeIraqiPhone('+14155552671')).toBeNull(); // US
    expect(normalizeIraqiPhone('+9648801234567')).toBeNull(); // not a 7-mobile
    expect(normalizeIraqiPhone('0770123456')).toBeNull(); // too short
    expect(normalizeIraqiPhone('077012345678')).toBeNull(); // too long
    expect(normalizeIraqiPhone('hello')).toBeNull();
    expect(normalizeIraqiPhone('')).toBeNull();
  });
});
