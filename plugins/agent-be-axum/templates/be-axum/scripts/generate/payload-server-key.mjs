#!/usr/bin/env node
/**
 * Writes a new P-256 key pair for the payload contract's key agreement, in the form
 * PAYLOAD_SERVER_JWK holds it: base64url of the UTF-8 JSON {kty, crv, d, x, y}. Run it on your
 * own machine and pipe it straight into the env file, so the private key never reaches a
 * terminal, a log or a transcript (.claude/PAYLOAD-CONTRACT.md, Keys):
 *
 *   node scripts/generate/payload-server-key.mjs | bash scripts/env/set.sh .env.development PAYLOAD_SERVER_JWK
 *
 * It refuses to write to a terminal. One key pair per environment: a new one makes every public
 * client negotiate again, which it does after its next ENVELOPE_REJECTED. Plain Node ESM, no
 * dependencies. Exit 0 written, 2 refused.
 */
import { generateKeyPairSync } from 'node:crypto';

if (process.stdout.isTTY) {
  console.error('payload-server-key: pipe this into scripts/env/set.sh; a private key never goes to a terminal');
  process.exit(2);
}
const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const { kty, crv, d, x, y } = privateKey.export({ format: 'jwk' });
process.stdout.write(Buffer.from(JSON.stringify({ kty, crv, d, x, y }), 'utf8').toString('base64url'));
