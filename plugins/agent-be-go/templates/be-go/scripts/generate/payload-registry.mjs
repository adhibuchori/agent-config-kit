#!/usr/bin/env node
/**
 * Writes the payload registry from the OpenAPI document and payload.config.json. The file is the one
 * the config's `registry` names, in its `language` (Go, Rust or Swift), and the exemptions there are
 * the only way an entry leaves `strict` (.claude/PAYLOAD-CONTRACT.md).
 *
 *   node scripts/generate/payload-registry.mjs
 *
 * Never edit the output by hand: a policy typed into it would be reverted by the next run, the
 * worst way for a security decision to disappear. Decide policies in payload.config.json
 * `exemptions`, with a reason, and run this again. scripts/check/payload-registry.mjs emits the
 * same file in memory and fails on any difference, so a hand edit blocks the gate instead.
 *
 * Plain Node ESM, no dependencies. Exit 0 written, 1 nothing written (no config, a config or a
 * spec that cannot be read).
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CONFIG_FILE,
  deriveEndpoints,
  emitRegistry,
  readPayloadConfig,
  readSpec,
} from '../lib/payload-registry.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

try {
  const config = readPayloadConfig(ROOT);
  if (!config) {
    console.error(`payload-registry: no ${CONFIG_FILE}; the payload contract is not adopted here.`);
    process.exit(1);
  }
  const endpoints = deriveEndpoints(readSpec(ROOT, config), config.exemptions);
  const out = join(ROOT, config.registry);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, emitRegistry(config, endpoints));
  console.log(`payload-registry: wrote ${endpoints.length} endpoint(s) to ${config.registry}`);
} catch (err) {
  console.error(`payload-registry: ${err.message}`);
  process.exit(1);
}
