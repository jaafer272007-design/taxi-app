import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { UpdateMeDto } from './update-me.dto';

/// Validation-layer tests: these mirror what the global ValidationPipe does
/// (plainToInstance + validate), so a failure here is a 400 at the endpoint.
describe('UpdateMeDto validation', () => {
  it('accepts a valid gender enum', () => {
    const dto = plainToInstance(UpdateMeDto, { gender: 'FEMALE' });
    expect(validateSync(dto)).toHaveLength(0);
  });

  it('rejects an invalid gender enum (→ 400)', () => {
    const dto = plainToInstance(UpdateMeDto, { gender: 'OTHER' });
    const errors = validateSync(dto);
    expect(errors).not.toHaveLength(0);
    expect(errors[0].property).toBe('gender');
  });

  it('allows a name-only update (gender optional)', () => {
    const dto = plainToInstance(UpdateMeDto, { name: 'علي حسن' });
    expect(validateSync(dto)).toHaveLength(0);
  });

  it('allows a gender-only update (name optional)', () => {
    const dto = plainToInstance(UpdateMeDto, { gender: 'MALE' });
    expect(validateSync(dto)).toHaveLength(0);
  });

  it('rejects a blank name when name is provided', () => {
    const dto = plainToInstance(UpdateMeDto, { name: '   ' });
    const errors = validateSync(dto);
    expect(errors.some((e) => e.property === 'name')).toBe(true);
  });
});
