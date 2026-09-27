// Merge the `coverage` block below into the `test` section of your vitest.config.ts.
// scripts/check/coverage-policy.mjs refuses to pass until coverage asks for 100% on the logic layer
// and every exclusion carries its reason.
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      /* Directory patterns: a file no test imports lands in the report at 0% instead of vanishing. */
      include: ['src/hooks/**', 'src/lib/**', 'src/store/**', 'src/i18n/**', 'src/proxy.ts'],
      thresholds: { statements: 100, branches: 100, functions: 100, lines: 100 },
      exclude: [
        '**/index.ts',
        'src/lib/api/generated/**',
        /* Static seed data: object literals with no branch to test. List each file by path. */
      ],
    },
  },
});
