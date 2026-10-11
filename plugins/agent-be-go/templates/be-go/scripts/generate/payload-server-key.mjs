#!/usr/bin/env node
/**
 * Makes a new P-256 key pair for the payload contract's key agreement, in the form PAYLOAD_SERVER_JWK
 * holds: base64url of the UTF-8 JWK text {kty, crv, d, x, y}.
 *
 * The output is a private key. Pipe it straight into the env file, through the kit's unlock flow
 * (docs/unlock.md), which masks it; never into a terminal log, a chat or a commit:
 *
 *   node scripts/generate/payload-server-key.mjs | bash scripts/env/set.sh .env.development PAYLOAD_SERVER_JWK
 *
 * A new pair per environment. Replacing one makes every client negotiate again: it drops its agreed
 * key after the first ENVELOPE_REJECTED, so no rotation slot is needed.
 */
import { generateKeyPairSync } from 'node:crypto';

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const { kty, crv, d, x, y } = privateKey.export({ format: 'jwk' });
process.stdout.write(Buffer.from(JSON.stringify({ kty, crv, d, x, y }), 'utf8').toString('base64url'));
