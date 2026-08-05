/**
 * Integration tests: they run against a REAL Postgres, so they are a separate
 * command from `npm test`. Keeping them out of the default run means the unit
 * suite stays hermetic and fast; CI runs BOTH (see .github/workflows/ci.yml),
 * so nothing here is optional in practice.
 *
 * The filename convention is `*.int-spec.ts`, which the unit config's
 * `.*\.spec\.ts$` deliberately does not match.
 */
module.exports = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: 'src',
  testRegex: '.*\\.int-spec\\.ts$',
  transform: { '^.+\\.(t|j)s$': 'ts-jest' },
  testEnvironment: 'node',
  // Real database round-trips; the default 5s is tight for the first connection.
  testTimeout: 30000,
  // One worker: these share a database, and the expiry sweep is global by
  // design — a parallel worker's fixtures would be swept mid-test.
  maxWorkers: 1,
};
