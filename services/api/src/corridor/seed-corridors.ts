import { buildCorridorGrid, CorridorSeed } from './corridor-grid';

/** The slice of PrismaClient this needs — so it is testable without a database. */
export interface CorridorStore {
  corridor: {
    createMany(args: {
      data: CorridorSeed[];
      skipDuplicates?: boolean;
    }): Promise<{ count: number }>;
    count(): Promise<number>;
  };
}

export interface CorridorSeedResult {
  /** Rows the grid defines — always 306. */
  expected: number;
  /** Rows this run actually inserted; 0 on a re-run. */
  created: number;
  /** Rows in the table afterwards. */
  total: number;
}

/**
 * Insert every missing corridor of the 18x17 grid. **Never touches a row that
 * already exists.**
 *
 * That is the important half, and it is enforced structurally rather than by
 * care: `createMany({ skipDuplicates: true })` has no update path at all, so the
 * seed *cannot* clobber a price the admin tuned by hand. An `upsert` with an
 * empty `update` would behave the same way today but is one careless edit away
 * from resetting every corridor in the country on the next deploy — the same
 * class of mistake as a seed that rewrites the super admin's password.
 *
 * It is also a single statement rather than 306 round trips, which matters when
 * this runs on every deploy.
 */
export async function seedCorridorGrid(store: CorridorStore): Promise<CorridorSeedResult> {
  const grid = buildCorridorGrid();
  const { count } = await store.corridor.createMany({
    data: grid,
    skipDuplicates: true,
  });
  return {
    expected: grid.length,
    created: count,
    total: await store.corridor.count(),
  };
}
