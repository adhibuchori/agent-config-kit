#!/usr/bin/env node
/**
 * Terms guard: the words a project has decided not to use about itself.
 *
 * Some words are claims. A title the law reserves, a guarantee the business cannot stand behind, a
 * name the product has retired: once one reaches shipped code, copy or a wire contract
 * it is a promise, so the words listed in `scripts/check/terms.config.json` fail the gate wherever
 * they appear. The vocabulary is the repo's own and starts empty.
 *
 * A line may still need one of them, to say what the product is NOT, or to name a third party's own
 * field. Those go in the config as an `allow` entry: the exact phrase, the one file it may appear
 * in, and the reason. The phrase is removed from the line before the line is checked, so the rest of
 * that line is still held to the rule. An entry whose phrase no longer appears in its file fails
 * too: a stale exemption is a hole waiting for a new sentence.
 *
 * Plain Node ESM with no dependencies, so the same file runs under bun in the TypeScript repos and
 * under the runner's node in the others. Exit code 1 on any hit, and on a vocabulary that scanned
 * no file, which is the roots being wrong rather than a clean result.
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const CONFIG = 'scripts/check/terms.config.json';
const SELF = new Set(['scripts/check/terms.mjs', CONFIG]);
const TEXT = /\.(ts|tsx|js|jsx|mjs|cjs|json|md|mdx|css|html|sql|ya?ml|toml|py|go|rs|swift|xcstrings)$/;

const fail = (message) => {
  console.error(`terms: ${message}`);
  process.exit(1);
};

const strings = (value) => Array.isArray(value) && value.every((item) => typeof item === 'string');
const filled = (value) => typeof value === 'string' && value !== '';

function readConfig() {
  const path = join(ROOT, CONFIG);
  if (!existsSync(path)) return null;
  let config;
  try {
    config = JSON.parse(readFileSync(path, 'utf8'));
  } catch (err) {
    return fail(`cannot read ${CONFIG}: ${err.message}`);
  }
  const shaped =
    strings(config?.roots) &&
    strings(config?.exclude) &&
    Array.isArray(config?.forbidden) &&
    config.forbidden.every((f) => filled(f?.term) && filled(f?.why)) &&
    Array.isArray(config?.allow) &&
    config.allow.every((a) => filled(a?.path) && filled(a?.phrase) && filled(a?.reason));
  /* An entry without its reason is refused here, not silently accepted. */
  return shaped ? config : fail(`${CONFIG} needs roots, exclude, forbidden {term, why} and allow {path, phrase, reason}`);
}

const config = readConfig();
if (!config || config.forbidden.length === 0) {
  console.log(`terms: no forbidden term listed in ${CONFIG}, nothing to check`);
  process.exit(0);
}

const families = config.forbidden.map(({ term, why }) => {
  try {
    return { pattern: new RegExp(term, 'gi'), why };
  } catch (err) {
    return fail(`forbidden term "${term}" is not a regular expression: ${err.message}`);
  }
});

/* The scan reads the index, not the worktree: that is what a commit records. Sessions sharing a
   checkout each commit their own paths, so the index can list a path another session has deleted
   from the worktree, and its content must still count for its allow entries. */
const listed = execFileSync('git', ['ls-files', '-z', '--', ...config.roots], { cwd: ROOT, encoding: 'utf8' });
const tracked = listed
  .split('\0')
  .filter((path) => path !== '' && TEXT.test(path) && !SELF.has(path) && !config.exclude.some((prefix) => path.startsWith(prefix)));

if (tracked.length === 0) fail(`no text file is tracked under ${config.roots.join(', ')}: nothing was checked`);

/** What the index holds for each path, read in one `git cat-file --batch`. */
function indexContents(paths) {
  const out = execFileSync('git', ['cat-file', '--batch'], {
    cwd: ROOT,
    input: paths.map((path) => `:${path}\n`).join(''),
    maxBuffer: Infinity,
  });
  const contents = new Map();
  let at = 0;
  for (const path of paths) {
    const headerEnd = out.indexOf('\n', at);
    const size = Number(out.toString('utf8', at, headerEnd).split(' ')[2]);
    if (!Number.isInteger(size)) fail(`the index holds no blob for ${path}`);
    const start = headerEnd + 1;
    contents.set(path, out.toString('utf8', start, start + size));
    at = start + size + 1;
  }
  return contents;
}

const hits = [];
const used = new Set();

for (const [path, content] of indexContents(tracked)) {
  const allows = config.allow.filter((a) => a.path === path);
  for (const [index, line] of content.split('\n').entries()) {
    let checked = line;
    for (const allow of allows) {
      if (checked.includes(allow.phrase)) {
        used.add(allow);
        checked = checked.split(allow.phrase).join(' ');
      }
    }
    for (const { pattern, why } of families) {
      for (const match of checked.matchAll(pattern)) hits.push(`  ${path}:${index + 1}  "${match[0]}": ${why}`);
    }
  }
}

const stale = config.allow.filter((a) => !used.has(a)).map((a) => `  ${a.path}  "${a.phrase}"`);

console.log(`terms: scanned ${tracked.length} files under ${config.roots.join(', ')}`);

if (hits.length > 0) {
  console.error(`\n${hits.length} forbidden term(s):\n${hits.join('\n')}`);
  console.error(`\nReword the line. If it must keep the word (a disclaimer, a third-party field), add an allow entry with its reason to ${CONFIG}.`);
}
if (stale.length > 0) {
  console.error(`\n${stale.length} stale allow entr${stale.length === 1 ? 'y' : 'ies'} (the phrase is gone from the file):\n${stale.join('\n')}`);
}
if (hits.length > 0 || stale.length > 0) process.exit(1);
