import type { KnipConfig } from 'knip';

/* Dead-code gate (`bun run check:dead-code`); the rule is .claude/rules/typescript/dead-code.md.
   Every entry below is reached by something Knip cannot follow, and says what. Listing `entry`
   replaces Knip's default entry files, so the server entry is named here too. */
const config: KnipConfig = {
  entry: [
    /* The server: started by path (`bun run src/index.ts`) and bundled by the `build` script. */
    'src/index.ts',
    /* Check scripts run by path from the shell (scripts/check/gates.list, the quality gate), which
       no import names. */
    'scripts/check/*.ts',
    /* The integration tier's gate (AGENTS.md Rule 20). Only this file may read the integration
       switch past the process.env lint rule, so it stays even while no `*.integration.test.ts`
       imports it yet: `bun run test:integration` is that tier. */
    'src/test/config.ts',
  ],
  /* A copy-me example for src/test/preload.ts, read by people, never imported. */
  ignore: ['.claude/test-preload.example.ts'],
  /* Exports used only inside their own file are reported too: drop `export` from them. */
  ignoreExportsUsedInFile: false,
};

export default config;
