import type { KnipConfig } from 'knip';

const config: KnipConfig = {
  /* Knip has no Nextra plugin: Nextra reads every `content/` page and `_meta` by filesystem
     convention, and the gates run the check scripts from shell (gates.list, quality-gate.sh). */
  entry: [
    'content/**/*.mdx',
    'content/**/_meta.{js,jsx,ts,tsx}',
    'scripts/check/*.{ts,mjs}',
    '.github/scripts/*.ts',
  ],
  /* Off by default without an @mdx-js dependency; on, it follows the imports in each page. */
  compilers: { mdx: true },
  ignoreExportsUsedInFile: false,
};

export default config;
