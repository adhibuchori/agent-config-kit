// Lets the kit's tests run the TypeScript check scripts on Node when Bun is not installed (CI).
// Node strips types by itself (22.18+); this hook adds what Bun resolves and Node does not: an
// extensionless relative import (`./codec`) and a folder import (`./dir` → `./dir/index.ts`).
// Loaded with `node --import <this file> script.ts`. Test tooling only; never shipped to a repo.
import { existsSync } from 'node:fs';
import { register } from 'node:module';
import { fileURLToPath } from 'node:url';

export async function resolve(specifier, context, next) {
  try {
    return await next(specifier, context);
  } catch (error) {
    const relative = specifier.startsWith('./') || specifier.startsWith('../');
    if (!relative || !context.parentURL) throw error;
    for (const suffix of ['.ts', '/index.ts']) {
      const candidate = new URL(specifier + suffix, context.parentURL);
      if (existsSync(fileURLToPath(candidate))) return next(candidate.href, context);
    }
    throw error;
  }
}

if (!process.env.TS_RESOLVE_REGISTERED) {
  process.env.TS_RESOLVE_REGISTERED = '1';
  register(import.meta.url);
}
