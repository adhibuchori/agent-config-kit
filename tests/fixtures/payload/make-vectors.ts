/**
 * Writes the payload test vectors every implementation of the envelope proves itself against.
 *
 * Run once, from the kit's TypeScript reference implementation, and commit the output. Never
 * regenerate to make a failing implementation pass: a mismatch means an implementation changed.
 *
 *   bun tests/fixtures/payload/make-vectors.ts > plugins/<p>/templates/<stack>/scripts/check/payload-vectors.json
 *
 * `agreements` answers the key agreement the AES vectors take as given: a fixed server keypair (as
 * PAYLOAD_SERVER_JWK holds it) and a fixed client keypair, the ECDH secret they share, the AES key
 * HKDF derives from it, and an envelope sealed under that key. node:crypto computes it, and the
 * reference implementation must open it from both sides before anything is written. `pointRejects`
 * are peer keys every implementation refuses with their code, a compressed point among them: some
 * libraries take one and others never do, so every implementation refuses it.
 */

import { createECDH, ECDH, hkdfSync } from 'node:crypto';
import { open, seal } from '../../../plugins/agent-be-hono/templates/be-hono/src/lib/payload/aes-gcm.ts';
import {
  toBase64Url,
  utf8Bytes,
  utf8String,
} from '../../../plugins/agent-be-hono/templates/be-hono/src/lib/payload/base64url.ts';
import {
  deriveSessionKey,
  importServerKeyPair,
} from '../../../plugins/agent-be-hono/templates/be-hono/src/lib/payload/ecdh.ts';
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

/* The key agreement. Both private scalars come from labels, like the AES key above; setPrivateKey
   refuses a scalar that is not below the curve's order. */
const INFO = 'payload-envelope/v1/browser';
const copy = (data: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(data);
const serverD = await labelled('agent-config-kit payload vectors: server key', 32);
const clientD = await labelled('agent-config-kit payload vectors: client key', 32);
const server = createECDH('prime256v1');
server.setPrivateKey(serverD);
const client = createECDH('prime256v1');
client.setPrivateKey(clientD);
const serverPublic = copy(server.getPublicKey());
const clientPublic = copy(client.getPublicKey());
const secret = copy(server.computeSecret(clientPublic));
if (toBase64Url(copy(client.computeSecret(serverPublic))) !== toBase64Url(secret)) {
  throw new Error('the two sides of the agreement derived different secrets');
}
const agreedBytes = new Uint8Array(hkdfSync('sha256', secret, new Uint8Array(0), INFO, 32));
const agreedKey = await crypto.subtle.importKey('raw', agreedBytes, { name: 'AES-GCM' }, false, ['encrypt']);
const jwkOf = (d: Uint8Array<ArrayBuffer>, point: Uint8Array<ArrayBuffer>) => ({
  kty: 'EC',
  crv: 'P-256',
  d: toBase64Url(d),
  x: toBase64Url(point.slice(1, 33)),
  y: toBase64Url(point.slice(33)),
});
const serverJwk = toBase64Url(utf8Bytes(JSON.stringify(jwkOf(serverD, serverPublic))));
const sealed = { kind: 'request', method: 'POST', pattern: '/api/notes', kid: 'ecdh', plaintext: { title: 'Groceries', done: false, tags: ['home'] } } as const;
const agreedAad = requestAad(sealed.method, sealed.pattern, sealed.kid, TS);
const agreedIv = await labelled('agent-config-kit payload vectors: nonce agreement', 12);
const agreedCt = await seal(agreedKey, agreedIv, utf8Bytes(JSON.stringify(sealed.plaintext)), agreedAad);

/* The reference implementation agrees before the answer is published: the server's side from the
   JWK, the client's side from its own scalar, each opening the sealed envelope. */
const serverPair = await importServerKeyPair(serverJwk);
if (serverPair.publicKey !== toBase64Url(serverPublic)) throw new Error('the JWK names another public key');
const clientKey = await crypto.subtle.importKey('jwk', jwkOf(clientD, clientPublic), { name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits']);
const sides = [
  [serverPair.privateKey, toBase64Url(clientPublic)],
  [clientKey, toBase64Url(serverPublic)],
] as const;
for (const [mine, theirs] of sides) {
  await open(await deriveSessionKey(mine, theirs), agreedIv, agreedCt, agreedAad);
}

/* Each bad point is what its name says: one off the curve, and one that is the client's own
   point, compressed. */
const offCurve = copy(clientPublic);
offCurve[64] = (offCurve[64] ?? 0) ^ 1;
let onCurve = true;
try {
  server.computeSecret(offCurve);
} catch {
  onCurve = false;
}
if (onCurve) throw new Error('the off-curve point is on the curve');
const compressed = copy(ECDH.convertKey(clientPublic, 'prime256v1', undefined, undefined, 'compressed') as Buffer);
const expanded = copy(ECDH.convertKey(compressed, 'prime256v1', undefined, undefined, 'uncompressed') as Buffer);
if (toBase64Url(expanded) !== toBase64Url(clientPublic)) throw new Error('the compressed point is another point');

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
  agreements: [
    {
      name: 'browser-or-app key agreement',
      info: INFO,
      serverJwk,
      serverPublic: toBase64Url(serverPublic),
      clientPrivate: toBase64Url(clientD),
      clientPublic: toBase64Url(clientPublic),
      sharedBytes: toBase64Url(secret),
      sessionBytes: toBase64Url(agreedBytes),
      vector: { ...sealed, ts: TS, aad: utf8String(agreedAad), iv: toBase64Url(agreedIv), ct: toBase64Url(agreedCt) },
    },
  ],
  pointRejects: [
    { name: 'not on the curve', point: toBase64Url(offCurve), code: 'ENVELOPE_MALFORMED' },
    { name: '64 bytes, no prefix', point: toBase64Url(clientPublic.slice(1)), code: 'ENVELOPE_MALFORMED' },
    { name: 'compressed point', point: toBase64Url(compressed), code: 'ENVELOPE_MALFORMED' },
  ],
};
console.log(JSON.stringify(out, null, 2));
