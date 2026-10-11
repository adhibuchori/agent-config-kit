#!/usr/bin/env node
/**
 * The static half of the payload contract for the Go, Rust and Swift stacks
 * (.claude/PAYLOAD-CONTRACT.md). The runtime half refuses an unsealed body at the boundary; this
 * refuses the registry, spec or config that would let one through.
 *
 *   1. The switch: payload.config.json says `strict`. Any other value is refused when the config is
 *      read, and `off` fails here: debug with PAYLOAD_MODE=off in your own shell instead.
 *   2. Registry drift: the registry file is byte for byte what the spec and the exemptions emit.
 *   3. Exemptions: each has a reason (the config is refused without one) and names an operation
 *      the spec still has.
 *   4. Swift: every operation ID the generated client sends (GeneratedSources/ beside the registry)
 *      is in the registry, so the middleware never meets a call it cannot place.
 *   5. Refusal codes: the spec's Problem.code lists the five ENVELOPE_* codes.
 *   6. Handshake: the operation `handshake` names exists, is a GET, and is exempted `none`; an app
 *      must name one.
 *   7. Peers (where checked out): the spec and the exemptions equal the peer's. A peer that is not
 *      checked out is reported as skipped, never passed.
 *
 * Without payload.config.json the contract is not adopted: it says so and passes.
 *
 *   node scripts/check/payload-registry.mjs
 *
 * Plain Node ESM, no dependencies. Exit 0 clean, 1 on any problem.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CONFIG_FILE,
  ENVELOPE_CODES,
  deriveEndpoints,
  emitRegistry,
  problemCodes,
  readPayloadConfig,
  readPeerConfig,
  readSpec,
  sortKeys,
} from '../lib/payload-registry.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const GENERATE = 'node scripts/generate/payload-registry.mjs';
const OPERATION_ID = /\bstatic\s+let\s+id\s*:\s*(?:Swift\.)?String\s*=\s*"((?:[^"\\]|\\.)*)"/g;
const problems = [];
const fail = (check, detail) => problems.push(`${check}: ${detail}`);
const say = (message) => console.log(`payload-registry: ${message}`);
const canonical = (value) => JSON.stringify(sortKeys(value));

function swiftFiles(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) swiftFiles(path, out);
    else if (entry.name.endsWith('.swift')) out.push(path);
  }
  return out;
}

/* 2. Registry drift */
function checkDrift(config, endpoints) {
  let want;
  try {
    want = emitRegistry(config, endpoints);
  } catch (err) {
    fail('registry', err.message);
    return;
  }
  const path = join(ROOT, config.registry);
  if (!existsSync(path)) {
    fail('registry drift', `${config.registry} is missing; run ${GENERATE}`);
    return;
  }
  const got = readFileSync(path, 'utf8').split('\n');
  const lines = want.split('\n');
  const first = got.findIndex((line, i) => line !== lines[i]);
  if (first === -1 && got.length === lines.length) return;
  const at = (first === -1 ? Math.min(got.length, lines.length) : first) + 1;
  fail(
    'registry drift',
    `${config.registry} differs from what ${config.spec} and the exemptions imply (first at line ${at}); run ${GENERATE}, never edit it by hand`,
  );
}

/* 4. Swift: the operation IDs the generated client sends */
function checkClient(config, endpoints) {
  const dir = join(dirname(join(ROOT, config.registry)), 'GeneratedSources');
  const rel = relative(ROOT, dir);
  if (!existsSync(dir)) {
    say(`SKIPPED the generated client: no ${rel}/ yet`);
    return;
  }
  const registered = new Set(endpoints.map((e) => e.operationId));
  const sent = new Set();
  for (const file of swiftFiles(dir)) {
    for (const match of readFileSync(file, 'utf8').matchAll(OPERATION_ID)) sent.add(match[1]);
  }
  if (sent.size === 0 && endpoints.length > 0) {
    fail('generated client', `found no operation ID in ${rel}/; the scan read nothing to compare`);
  }
  for (const id of [...sent].sort()) {
    if (!registered.has(id)) {
      fail(
        'unregistered operation',
        `${rel}/ sends "${id}", which ${config.registry} does not hold; copy the backend's spec and run ${GENERATE}`,
      );
    }
  }
}

/* 5. Refusal codes */
function checkCodes(config, spec) {
  const codes = problemCodes(spec);
  if (!codes) {
    fail(
      'refusal codes',
      `${config.spec} has no Problem.code enum; list ${ENVELOPE_CODES.join(', ')} in it`,
    );
    return;
  }
  const missing = ENVELOPE_CODES.filter((code) => !codes.includes(code));
  if (missing.length > 0) {
    fail(
      'refusal codes',
      `Problem.code in ${config.spec} lacks ${missing.join(', ')}; a refusal is a code the spec lists`,
    );
  }
}

/* 6. Handshake */
function checkHandshake(config, endpoints) {
  if (!config.handshake) {
    if (config.language === 'swift') {
      fail(
        'handshake',
        `an app agrees its key through the handshake; name its operationId in ${CONFIG_FILE} "handshake"`,
      );
    }
    return;
  }
  const op = endpoints.find((e) => e.operationId === config.handshake);
  if (!op) {
    fail(
      'handshake',
      `${config.spec} has no operation "${config.handshake}"; add GET /api/payload/handshake (200 {publicKey, mode}), or drop "handshake" where only servers call`,
    );
    return;
  }
  if (op.method !== 'GET') {
    fail('handshake', `"${config.handshake}" is ${op.method} ${op.route}; the handshake is a GET`);
  }
  if (op.policy !== 'none') {
    fail(
      'handshake',
      `${op.method} ${op.pattern} is "${op.policy}"; exempt it "none" in ${CONFIG_FILE}: it hands out the key, so nothing can be sealed yet`,
    );
  }
}

/* 7. Peers */
function checkPeer(config, spec, peer) {
  const root = resolve(ROOT, peer.root);
  let theirs;
  try {
    theirs = readPeerConfig(root);
  } catch (err) {
    fail('peer', `${peer.name}: ${err.message}`);
    return;
  }
  if (!theirs) {
    say(`SKIPPED peer ${peer.name}: no ${CONFIG_FILE} at ${peer.root} (not checked out here)`);
    return;
  }
  const theirSpec = join(root, theirs.spec);
  if (spec && !existsSync(theirSpec)) {
    say(`SKIPPED spec parity with ${peer.name}: no ${theirs.spec} there`);
  } else if (spec) {
    let same = false;
    try {
      same = canonical(spec) === canonical(JSON.parse(readFileSync(theirSpec, 'utf8')));
    } catch {
      /* A copy that does not parse differs too. */
    }
    if (!same) {
      fail(
        'spec parity',
        `${config.spec} differs from ${peer.name}'s ${theirs.spec}; copy the owner's spec and run ${GENERATE}`,
      );
    }
  }
  if (canonical(config.exemptions) !== canonical(theirs.exemptions)) {
    fail(
      'policy parity',
      `the exemptions in ${CONFIG_FILE} differ from ${peer.name}'s; both sides must seal the same routes`,
    );
  }
}

let config;
try {
  config = readPayloadConfig(ROOT);
} catch (err) {
  console.error(`payload-registry: ✗ ${err.message}`);
  process.exit(1);
}
if (!config) {
  say(`no ${CONFIG_FILE}: this repo has not adopted the payload contract; nothing to check.`);
  process.exit(0);
}

/* 1. The switch */
if (config.encryption !== 'strict') {
  fail(
    'switch',
    `${CONFIG_FILE} says "${config.encryption}"; commit "strict" and debug with PAYLOAD_MODE=off in your own shell`,
  );
}

let spec = null;
let endpoints = [];
try {
  spec = readSpec(ROOT, config);
  endpoints = deriveEndpoints(spec, config.exemptions);
} catch (err) {
  fail('spec', `${err.message}; then run ${GENERATE}`);
}
if (spec) {
  checkDrift(config, endpoints);
  /* 3. Exemptions: the reasons were required when the config was read; here, stale ones. */
  const routes = new Set(endpoints.map((e) => `${e.method} ${e.pattern}`));
  for (const route of Object.keys(config.exemptions)) {
    if (!routes.has(route)) {
      fail(
        'stale exemption',
        `${route} is exempted in ${CONFIG_FILE} but ${config.spec} has no such operation`,
      );
    }
  }
  if (config.language === 'swift') checkClient(config, endpoints);
  checkCodes(config, spec);
  checkHandshake(config, endpoints);
}
for (const peer of config.peers) checkPeer(config, spec, peer);

if (problems.length > 0) {
  console.error(`payload-registry: ✗ ${problems.length} problem(s):`);
  for (const problem of problems) console.error(`  ${problem}`);
  console.error('  See .claude/PAYLOAD-CONTRACT.md.');
  process.exit(1);
}
say(
  `✓ ${endpoints.length} endpoint(s) in ${config.registry} (${config.language}); peers checked: ${config.peers.length}; all checks passed.`,
);
