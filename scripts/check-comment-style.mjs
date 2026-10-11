#!/usr/bin/env node
/**
 * Comment style for this repository's JavaScript and TypeScript: block comments only.
 *
 * `/** … *\/` documents a file or a declaration, `/* … *\/` is every other note, and `//` is kept for
 * the directives tools read (@ts-expect-error, @ts-ignore, @ts-check, @ts-nocheck, oxlint-disable,
 * eslint-disable, biome-ignore, v8 ignore, triple-slash references). The same standard the fe-nextjs
 * template enforces in users' repos (`.github/scripts/check-comment-style.ts`), here for the kit's own
 * scripts, actions, templates and tests.
 *
 *   node scripts/check-comment-style.mjs          report every stray `//` comment; exit 1 if any
 *   node scripts/check-comment-style.mjs --fix    rewrite them as block comments, then report
 *   node scripts/check-comment-style.mjs --root <dir> [--fix] [file...]
 *
 * The scan is a small tokenizer, so `//` inside a string, a template literal or a regular expression
 * is never read as a comment. `--fix` turns a run of whole-line comments into one block (a file header
 * or the note right above a declaration becomes `/** … *\/`) and a comment after code into `/* … *\/`
 * on the same line. A comment that holds `*\/` cannot become a block and is reported instead.
 *
 * Exit 0 clean, 1 a stray comment (after --fix: one that could not be rewritten), 2 bad usage or no
 * file found.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const DIRECTIVE =
  /^\/\/\/?\s*(@ts-expect-error|@ts-ignore|@ts-check|@ts-nocheck|oxlint-disable|eslint-disable|biome-ignore|v8 ignore|<reference\s)/;
const PATTERNS = ['*.js', '*.mjs', '*.cjs', '*.ts', '*.tsx', '*.mts', '*.cts'];
/* Third-party and generated text: installed packages, tool lockfile folders, generator output. */
const EXCLUDED = /(^|\/)(node_modules|\.github\/tools|generated)\/|\.generated\.[cm]?[jt]sx?$|(^|\/)next-env\.d\.ts$/;
const VALUE_CANNOT_FOLLOW = /[\w$)\]]$/;
const KEYWORDS_BEFORE_REGEX = /\b(return|typeof|instanceof|in|of|new|delete|void|throw|case|do|else|yield|await)$/;
const DECLARATION = /^\s*(export\s+)?(default\s+)?(async\s+)?(function\b|class\b|const\b|let\b|var\b|interface\b|type\b|enum\b)/;

function usage(message) {
  console.error(`check-comment-style: ${message}`);
  console.error('usage: node scripts/check-comment-style.mjs [--fix] [--root <dir>] [file...]');
  process.exit(2);
}

/** Every `//` comment in the source: its offsets, its text, and whether code precedes it on its line. */
function lineComments(source) {
  const found = [];
  const templateStack = [];
  const n = source.length;
  let i = 0;
  /* Text since the last token boundary: decides whether a `/` starts a regular expression. */
  let prev = '';
  const skipTemplate = () => {
    while (i < n) {
      if (source[i] === '\\') {
        i += 2;
        continue;
      }
      if (source[i] === '`') {
        i++;
        return;
      }
      if (source[i] === '$' && source[i + 1] === '{') {
        templateStack.push(1);
        i += 2;
        return;
      }
      i++;
    }
  };
  while (i < n) {
    const c = source[i];
    const next = source[i + 1];
    if (c === '\n') {
      i++;
      prev = '';
      continue;
    }
    if (c === '/' && next === '/') {
      const end = source.indexOf('\n', i) === -1 ? n : source.indexOf('\n', i);
      const lineStart = source.lastIndexOf('\n', i - 1) + 1;
      found.push({
        start: i,
        end,
        text: source.slice(i, end).trimEnd(),
        trailing: source.slice(lineStart, i).trim() !== '',
      });
      i = end;
      continue;
    }
    if (c === '/' && next === '*') {
      const end = source.indexOf('*/', i + 2);
      i = end === -1 ? n : end + 2;
      prev = ' ';
      continue;
    }
    if (c === '"' || c === "'") {
      i++;
      while (i < n && source[i] !== c && source[i] !== '\n') {
        if (source[i] === '\\') i++;
        i++;
      }
      i++;
      prev = 'x';
      continue;
    }
    if (c === '`') {
      i++;
      skipTemplate();
      prev = 'x';
      continue;
    }
    if (c === '}' && templateStack.length > 0) {
      templateStack.pop();
      i++;
      skipTemplate();
      prev = 'x';
      continue;
    }
    if (c === '/') {
      const trimmed = prev.trimEnd();
      if (trimmed === '' || !VALUE_CANNOT_FOLLOW.test(trimmed) || KEYWORDS_BEFORE_REGEX.test(trimmed)) {
        i++;
        let inClass = false;
        while (i < n && source[i] !== '\n') {
          if (source[i] === '\\') {
            i += 2;
            continue;
          }
          if (source[i] === '[') inClass = true;
          else if (source[i] === ']') inClass = false;
          else if (source[i] === '/' && !inClass) {
            i++;
            break;
          }
          i++;
        }
        prev = 'x';
        continue;
      }
    }
    prev = (prev + c).slice(-32);
    i++;
  }
  return found;
}

const strays = (source) => lineComments(source).filter((c) => !DIRECTIVE.test(c.text));
const bodyOf = (text) => text.replace(/^\/\/\s?/, '');

/** The source with every stray comment rewritten as a block comment, and the ones that cannot be. */
function rewrite(source) {
  const lines = source.split('\n');
  const offsets = [];
  let at = 0;
  for (const l of lines) {
    offsets.push(at);
    at += l.length + 1;
  }
  const lineOf = (pos) => {
    let lo = 0;
    let hi = offsets.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (offsets[mid] <= pos) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  };
  const left = [];
  const edits = new Map();
  const comments = strays(source);
  for (let k = 0; k < comments.length; k++) {
    const c = comments[k];
    const row = lineOf(c.start);
    if (c.trailing) {
      if (c.text.includes('*/')) left.push({ line: row + 1, text: c.text });
      else edits.set(row, { kind: 'trailing', col: c.start - offsets[row], body: bodyOf(c.text) });
      continue;
    }
    /* A run: whole-line comments on consecutive lines at the same indentation. */
    const indent = lines[row].slice(0, lines[row].indexOf('//'));
    const run = [c];
    while (k + 1 < comments.length) {
      const d = comments[k + 1];
      const r = lineOf(d.start);
      if (d.trailing || r !== row + run.length || !lines[r].startsWith(`${indent}//`)) break;
      run.push(d);
      k++;
    }
    /* A line that holds the block terminator keeps its whole run as it is: a block split around it
       would read as three notes. */
    const blocked = run.filter((d) => d.text.includes('*/'));
    if (blocked.length > 0) {
      for (const d of blocked) left.push({ line: lineOf(d.start) + 1, text: d.text });
      continue;
    }
    const first = row;
    const last = row + run.length - 1;
    const before = lines.slice(0, first).filter((l) => l.trim() !== '' && !l.startsWith('#!'));
    const after = lines.slice(last + 1).find((l) => l.trim() !== '') ?? '';
    const doc = before.length === 0 || DECLARATION.test(after);
    const bodies = run.map((d) => bodyOf(d.text));
    let block;
    if (doc && (bodies.length > 1 || indent === '')) {
      block = [`${indent}/**`, ...bodies.map((b) => (b ? `${indent} * ${b}` : `${indent} *`)), `${indent} */`];
    } else if (bodies.length === 1) {
      block = [`${indent}/* ${bodies[0]} */`];
    } else {
      block = bodies.map((b, j) => {
        const lead = j === 0 ? `${indent}/* ` : `${indent}   `;
        return `${lead}${b}${j === bodies.length - 1 ? ' */' : ''}`.trimEnd();
      });
    }
    edits.set(first, { kind: 'block', last, block });
  }
  const out = [];
  for (let r = 0; r < lines.length; r++) {
    const e = edits.get(r);
    if (!e) {
      out.push(lines[r]);
    } else if (e.kind === 'trailing') {
      out.push(`${lines[r].slice(0, e.col).trimEnd()} /* ${e.body} */`);
    } else {
      out.push(...e.block);
      r = e.last;
    }
  }
  return { text: out.join('\n'), left };
}

const argv = process.argv.slice(2);
let fix = false;
let root = process.cwd();
const named = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--fix') fix = true;
  else if (argv[i] === '--root') root = resolve(argv[++i] ?? usage('--root needs a folder'));
  else if (argv[i].startsWith('-')) usage(`unknown option ${argv[i]}`);
  else named.push(argv[i]);
}

let files = named;
if (files.length === 0) {
  try {
    files = execFileSync('git', ['-C', root, 'ls-files', '--', ...PATTERNS], { encoding: 'utf8' }).split('\n').filter(Boolean);
  } catch {
    usage(`${root} is not a git checkout`);
  }
}
files = files.filter((f) => !EXCLUDED.test(f));
/* A shallow or broken checkout can list nothing; that is not a pass. */
if (files.length === 0) usage('no JavaScript or TypeScript file found');

let total = 0;
let rewritten = 0;
for (const file of files) {
  const path = join(root, file);
  const source = readFileSync(path, 'utf8');
  if (fix) {
    const { text, left } = rewrite(source);
    if (text !== source) {
      writeFileSync(path, text);
      rewritten++;
    }
    for (const v of left) console.log(`${file}:${v.line} — holds "*/", rewrite it by hand: ${v.text}`);
    total += left.length;
    continue;
  }
  for (const c of strays(source)) {
    const line = source.slice(0, c.start).split('\n').length;
    console.log(`${file}:${line} — stray \`//\` comment: ${c.text}`);
    total++;
  }
}
if (fix) console.log(`check-comment-style: rewrote ${rewritten} file(s)`);
if (total > 0) {
  console.log(`\n${total} stray \`//\` comment(s) in the ${files.length} file(s) scanned. Use /** */ for a file or a declaration, /* */ for other notes; // only for tool directives.`);
  process.exit(1);
}
console.log(`check-comment-style: ${files.length} file(s), no stray \`//\` comment`);
