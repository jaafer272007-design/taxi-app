import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { CreateCorridorDto } from './create-corridor.dto';
import { UpdateCorridorDto } from './update-corridor.dto';

/// Validation-layer tests mirror the global ValidationPipe, so a failure here is
/// a 400 at the endpoint. Cross-field price ordering is NOT here — it needs the
/// stored row on update, so it lives in CorridorService (see its spec).
describe('Corridor DTO validation', () => {
  const BAND = {
    suggestedPricePerSeat: 6000,
    minPricePerSeat: 3000,
    maxPricePerSeat: 12000,
  };

  describe('CreateCorridorDto', () => {
    it('accepts two canonical cities + a positive integer price band', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Najaf',
        destCity: 'Baghdad',
        ...BAND,
      });
      expect(validateSync(dto)).toHaveLength(0);
    });

    it('rejects an origin city outside the canonical list (→ 400)', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Atlantis',
        destCity: 'Baghdad',
        ...BAND,
      });
      const errors = validateSync(dto);
      expect(errors.some((e) => e.property === 'originCity')).toBe(true);
    });

    it('requires all three prices', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Najaf',
        destCity: 'Baghdad',
      });
      const failed = validateSync(dto).map((e) => e.property);
      expect(failed).toEqual(
        expect.arrayContaining([
          'suggestedPricePerSeat',
          'minPricePerSeat',
          'maxPricePerSeat',
        ]),
      );
    });

    it.each([
      ['suggestedPricePerSeat', { suggestedPricePerSeat: 0 }],
      ['minPricePerSeat', { minPricePerSeat: 0 }],
      ['maxPricePerSeat', { maxPricePerSeat: -1 }],
    ])('rejects a zero / negative %s', (property, override) => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Najaf',
        destCity: 'Baghdad',
        ...BAND,
        ...override,
      });
      expect(validateSync(dto).some((e) => e.property === property)).toBe(true);
    });

    it('rejects a fractional price — IQD has no fractions', () => {
      const dto = plainToInstance(CreateCorridorDto, {
        originCity: 'Najaf',
        destCity: 'Baghdad',
        ...BAND,
        suggestedPricePerSeat: 6000.5,
      });
      expect(validateSync(dto).some((e) => e.property === 'suggestedPricePerSeat')).toBe(
        true,
      );
    });
  });

  describe('UpdateCorridorDto', () => {
    it('allows a suggestion-only update', () => {
      const dto = plainToInstance(UpdateCorridorDto, { suggestedPricePerSeat: 7000 });
      expect(validateSync(dto)).toHaveLength(0);
    });

    it('allows an all-three price update', () => {
      const dto = plainToInstance(UpdateCorridorDto, {
        minPricePerSeat: 8000,
        suggestedPricePerSeat: 12000,
        maxPricePerSeat: 20000,
      });
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

    it('rejects a zero min price', () => {
      const dto = plainToInstance(UpdateCorridorDto, { minPricePerSeat: 0 });
      expect(validateSync(dto).some((e) => e.property === 'minPricePerSeat')).toBe(true);
    });
  });
});
