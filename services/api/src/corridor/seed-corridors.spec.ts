import { CorridorSeed } from './corridor-grid';
import { CorridorStore, seedCorridorGrid } from './seed-corridors';

/**
 * An in-memory stand-in for the two Prisma calls the seed uses, honouring the
 * (originCity, destCity) unique index the real table has.
 */
function fakeStore(existing: Array<Partial<CorridorSeed>> = []) {
  const rows: CorridorSeed[] = existing.map((e) => ({
    originCity: 'Najaf',
    destCity: 'Karbala',
    suggestedPricePerSeat: 12000,
    minPricePerSeat: 7000,
    maxPricePerSeat: 19000,
    active: true,
    ...e,
  }) as CorridorSeed);

  const key = (r: { originCity: string; destCity: string }) => `${r.originCity}→${r.destCity}`;

  return {
    rows,
    corridor: {
      createMany: jest.fn(
        async ({ data, skipDuplicates }: { data: CorridorSeed[]; skipDuplicates?: boolean }) => {
          const seen = new Set(rows.map(key));
          let count = 0;
          for (const row of data) {
            if (seen.has(key(row))) {
              if (!skipDuplicates) {
                throw new Error(`unique constraint violated on ${key(row)}`);
              }
              continue;
            }
            seen.add(key(row));
            rows.push(row);
            count++;
          }
          return { count };
        },
      ),
      count: jest.fn(async () => rows.length),
    },
  };
}

describe('seedCorridorGrid', () => {
  it('creates the whole grid on an empty database', async () => {
    const store = fakeStore();

    const result = await seedCorridorGrid(store as unknown as CorridorStore);

    expect(result).toEqual({ expected: 306, created: 306, total: 306 });
  });

  it('is idempotent — a second run creates nothing', async () => {
    const store = fakeStore();

    await seedCorridorGrid(store as unknown as CorridorStore);
    const second = await seedCorridorGrid(store as unknown as CorridorStore);

    expect(second).toEqual({ expected: 306, created: 0, total: 306 });
    expect(store.rows).toHaveLength(306);
  });

  it('NEVER overwrites a price on a corridor that already exists', async () => {
    // The important half. The admin may have tuned Najaf→Karbala by hand; a
    // deploy that silently reset it is the same class of bug as a seed that
    // rewrites the super admin's password.
    const store = fakeStore([
      {
        originCity: 'Najaf',
        destCity: 'Karbala',
        suggestedPricePerSeat: 25000,
        minPricePerSeat: 20000,
        maxPricePerSeat: 30000,
      },
    ]);

    await seedCorridorGrid(store as unknown as CorridorStore);

    const tuned = store.rows.find(
      (r) => r.originCity === 'Najaf' && r.destCity === 'Karbala',
    );
    expect(tuned).toMatchObject({
      suggestedPricePerSeat: 25000,
      minPricePerSeat: 20000,
      maxPricePerSeat: 30000,
    });
    // …and the other 305 were still filled in around it.
    expect(store.rows).toHaveLength(306);
  });

  it("does not re-activate a corridor the admin deliberately disabled", async () => {
    // Same reasoning as the price: `active: false` is an admin decision, and a
    // deploy must not quietly put a disabled route back on sale.
    const store = fakeStore([
      { originCity: 'Basra', destCity: 'Duhok', active: false },
    ]);

    await seedCorridorGrid(store as unknown as CorridorStore);

    expect(
      store.rows.find((r) => r.originCity === 'Basra' && r.destCity === 'Duhok')?.active,
    ).toBe(false);
  });

  it('relies on skipDuplicates rather than on reading first', async () => {
    // Structural, not incidental: createMany has no update path, so the seed
    // *cannot* clobber a tuned row even if someone edits it carelessly later.
    const store = fakeStore();

    await seedCorridorGrid(store as unknown as CorridorStore);

    expect(store.corridor.createMany).toHaveBeenCalledTimes(1);
    expect(store.corridor.createMany.mock.calls[0][0].skipDuplicates).toBe(true);
  });

  it('fills in gaps left by a partially-seeded database', async () => {
    const store = fakeStore([
      { originCity: 'Najaf', destCity: 'Karbala' },
      { originCity: 'Karbala', destCity: 'Najaf' },
    ]);

    const result = await seedCorridorGrid(store as unknown as CorridorStore);

    expect(result.created).toBe(304);
    expect(result.total).toBe(306);
  });
});
