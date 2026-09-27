/**
 * Writes the payload test vectors every implementation of the envelope proves itself against.
 *
 * Run once, from the kit's TypeScript reference implementation, and commit the output. Never
 * regenerate to make a failing implementation pass: a mismatch means an implementation changed.
 *
 *   bun tests/fixtures/payload/make-vectors.ts > plugins/<p>/templates/<stack>/scripts/check/payload-vectors.json
 */

import { seal } from '../../../plugins/agent-be-hono/templates/be-hono/src/lib/payload/aes-gcm.ts';
import {
  toBase64Url,
  utf8Bytes,
  utf8String,
} from '../../../plugins/agent-be-hono/templates/be-hono/src/lib/payload/base64url.ts';
import {
  requestAad,
  responseAad,
} from '../../../plugins/agent-be-hono/templates/be-hono/src/lib/payload/envelope.ts';

/* Published test material derived from fixed labels, never a real key. */
async function labelled(label: string, length: number): Promise<Uint8Array<ArrayBuffer>> {
  const digest = await crypto.subtle.digest('SHA-256', utf8Bytes(label));
  return new Uint8Array(digest.slice(0, length));
}
const keyBytes = await labelled('agent-config-kit payload vectors: key', 32);
const TS = 1_767_225_600_000;

const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt']);

type Base = { name: string; pattern: string; kid: string; plaintext: unknown };
type Req = Base & { kind: 'request'; method: string };
type Res = Base & { kind: 'response'; status: number };

const cases: (Req | Res)[] = [
  { name: 'request', kind: 'request', method: 'POST', pattern: '/api/notes', kid: 'k1', plaintext: { title: 'Groceries', done: false, tags: ['home'] } },
  { name: 'response', kind: 'response', status: 201, pattern: '/api/notes/:id', kid: 'k1', plaintext: { id: 'n_42', text: 'Multi-byte text survives: café, ümlaut, 東京, ✓' } },
  { name: 'agreed-key', kind: 'request', method: 'DELETE', pattern: '/api/notes/:id', kid: 'ecdh', plaintext: null },
];

const vectors = [];
for (const c of cases) {
  const aad = c.kind === 'request' ? requestAad(c.method, c.pattern, c.kid, TS) : responseAad(c.status, c.pattern, c.kid, TS);
  /* A nonce of its own per vector: even test material never shows a reused nonce. */
  const iv = await labelled(`agent-config-kit payload vectors: nonce ${c.name}`, 12);
  const ct = await seal(key, iv, utf8Bytes(JSON.stringify(c.plaintext)), aad);
  vectors.push({ ...c, ts: TS, aad: utf8String(aad), iv: toBase64Url(iv), ct: toBase64Url(ct) });
}

const out = {
  about: [
    'Payload envelope test vectors (.claude/PAYLOAD-CONTRACT.md § Tests and interop).',
    'Every implementation proves two things against this file: its AAD builder produces `aad` byte for byte,',
    'and it opens `ct` back to `plaintext` with the AES key in `testBytes`. It must also refuse every entry in `rejects`.',
    'At the AEAD layer, below the freshness check, so a fixed `ts` never expires. The key is published test',
    'material, never a real key. Identical in every repo that speaks the format; never regenerate it to make',
    'a failing implementation pass.',
  ],
  testBytes: toBase64Url(keyBytes),
  vectors,
  rejects: [
    { name: 'another route', vector: 'request', aad: '1.POST./api/notes/:id/share.k1.' + TS, why: 'the AAD names the route pattern' },
    { name: 'another method', vector: 'request', aad: '1.PUT./api/notes.k1.' + TS, why: 'the AAD names the method' },
    { name: 'another status', vector: 'response', aad: '1.200./api/notes/:id.k1.' + TS, why: 'the AAD names the status' },
    { name: 'another key id', vector: 'response', aad: '1.201./api/notes/:id.k2.' + TS, why: 'the AAD names the key id' },
    { name: 'another timestamp', vector: 'agreed-key', aad: '1.DELETE./api/notes/:id.ecdh.' + (TS + 1), why: 'the AAD names the timestamp' },
  ],
};
console.log(JSON.stringify(out, null, 2));
