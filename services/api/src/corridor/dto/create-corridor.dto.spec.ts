import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { CreateCorridorDto } from './create-corridor.dto';
import { UpdateCorridorDto } from './update-corridor.dto';

/// Validation-layer tests mirror the global ValidationPipe, so a failure here is
/// a 400 at the endpoint.
describe('Corridor DTO validation', () => {
  describe('CreateCorridorDto', () => {
    it('accepts two canonical cities + a positive integer price', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Najaf',
        destCity: 'Baghdad',
        pricePerSeat: 6000,
      });
      expect(validateSync(dto)).toHaveLength(0);
    });

    it('rejects an origin city outside the canonical list (→ 400)', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Atlantis',
        destCity: 'Baghdad',
        pricePerSeat: 6000,
      });
      const errors = validateSync(dto);
      expect(errors.some((e) => e.property === 'originCity')).toBe(true);
    });

    it('rejects a non-integer / zero price', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Najaf',
        destCity: 'Baghdad',
        pricePerSeat: 0,
      });
      expect(validateSync(dto).some((e) => e.property === 'pricePerSeat')).toBe(true);
    });
  });

  describe('UpdateCorridorDto', () => {
    it('allows a price-only update', () => {
      const dto = plainToInstance(UpdateCorridorDto, { pricePerSeat: 7000 });
      expect(validateSync(dto)).toHaveLength(0);
    });

    it('allows an active toggle', () => {
      const dto = plainToInstance(UpdateCorridorDto, { active: false });
      expect(validateSync(dto)).toHaveLength(0);
    });

    it('rejects an invalid destination city', () => {
      const dto = plainToInstance(UpdateCorridorDto, { destCity: 'Nowhere' });
      expect(validateSync(dto).some((e) => e.property === 'destCity')).toBe(true);
    });
  });
});
