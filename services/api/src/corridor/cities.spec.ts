import { IRAQI_CITIES, cityAr, isIraqiCity, routeLabelAr } from './cities';

describe('canonical cities', () => {
  it('is the 18-governorate list, with no duplicates', () => {
    expect(IRAQI_CITIES).toHaveLength(18);
    expect(new Set(IRAQI_CITIES).size).toBe(18);
  });

  it('accepts a canonical city and rejects anything else', () => {
    expect(isIraqiCity('Najaf')).toBe(true);
    expect(isIraqiCity('najaf')).toBe(false);
    expect(isIraqiCity('Atlantis')).toBe(false);
  });
});

describe('Arabic names', () => {
  // The guard that makes a fourth copy of this list safe. Notification copy is
  // composed server-side and stored ready to render, so a missing translation
  // does not fall back to some other layer — it ships «Najaf إلى Karbala» to a
  // rider. A nineteenth city must fail HERE, not in a screenshot.
  it('covers EVERY canonical city', () => {
    const missing = IRAQI_CITIES.filter((key) => cityAr(key) === key);
    expect(missing).toEqual([]);
  });

  it('returns Arabic script, never the English key', () => {
    for (const key of IRAQI_CITIES) {
      expect(cityAr(key)).toMatch(/^[؀-ۿ\s]+$/);
    }
  });

  it('falls back to the key for an unknown value rather than throwing', () => {
    expect(cityAr('Atlantis')).toBe('Atlantis');
  });
});

describe('routeLabelAr', () => {
  it('joins the cities with the WORD «إلى»', () => {
    expect(routeLabelAr('Najaf', 'Karbala')).toBe('النجف إلى كربلاء');
  });

  it('never uses an arrow — the bundled Cairo has no arrow glyph', () => {
    // A `→` renders as a tofu box in the apps (CLAUDE.md → Glyph coverage), and
    // this string is also read by the notification centre, which uses Cairo.
    const label = routeLabelAr('Baghdad', 'Basra');
    expect(label).not.toMatch(/[←→⟵⟶↔]/);
  });

  it('carries no digits, so the ٠-dot hazard cannot arise in it', () => {
    // The route label is embedded in notification bodies that render on
    // surfaces we do not control. Keeping it digit-free means no separator in
    // the surrounding copy can ever land beside an Arabic-Indic numeral.
    expect(routeLabelAr('Najaf', 'Karbala')).not.toMatch(/[0-9٠-٩]/);
  });
});
