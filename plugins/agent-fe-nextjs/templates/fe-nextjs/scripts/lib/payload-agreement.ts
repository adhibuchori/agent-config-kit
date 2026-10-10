/**
 * The key-agreement half of the shared payload vectors, which scripts/check/crypto-interop.ts runs
 * beside the AES vectors (.claude/PAYLOAD-CONTRACT.md § Tests and interop).
 *
 * The AES vectors start from a key both sides already hold. A public client (a browser, a native
 * app) agrees its key instead, so a copy that derived it wrongly would open every AES vector and
 * still fail against its peer. Each entry in `agreements` is checked twice: with WebCrypto alone
 * (the ECDH secret from both sides, then the key HKDF derives from it), so the published answer is
 * sound; and through this repo's src/lib/payload (the server key from its JWK, the session key from
 * either side opening the sealed envelope, the AAD byte for byte), so this copy reaches the same
 * key. Every entry in `pointRejects` must be refused with its code.
 */

import type * as AesModule from '../../src/lib/payload/aes-gcm';
import type * as B64Module from '../../src/lib/payload/base64url';
import type * as EcdhModule from '../../src/lib/payload/ecdh';
import type * as EnvModule from '../../src/lib/payload/envelope';

/** The copy of src/lib/payload the agreement runs through. */
export interface AgreementImpl {
  aes: typeof AesModule;
  b64: typeof B64Module;
  ecdh: typeof EcdhModule;
  env: typeof EnvModule;
}

/** One published key agreement and the envelope sealed under its key. */
export interface Agreement {
  name: string;
  info: string;
  serverJwk: string;
  serverPublic: string;
  clientPrivate: string;
  clientPublic: string;
  sharedBytes: string;
  sessionBytes: string;
  vector: {
    kind: string;
    method?: string;
    status?: number;
    pattern: string;
    kid: string;
    plaintext: unknown;
    ts: number;
    aad: string;
    iv: string;
    ct: string;
  };
}

/** A peer public key every implementation refuses, and the code it refuses it with. */
export interface PointReject {
  name: string;
  point: string;
  code: string;
}

/** What the agreement vectors found: the problems, and how much was checked. */
export interface AgreementReport {
  problems: string[];
  agreements: number;
  points: number;
}

const CURVE: EcKeyImportParams = { name: 'ECDH', namedCurve: 'P-256' };

const reason = (error: unknown): string => (error instanceof Error ? error.message : String(error));

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/* A private key from its scalar and its own public point, the only form WebCrypto imports. */
async function privateKey(b64: AgreementImpl['b64'], d: string, point: string): Promise<CryptoKey> {
  const raw = b64.fromBase64Url(point);
  const x = b64.toBase64Url(raw.slice(1, 33));
  const y = b64.toBase64Url(raw.slice(33));
  const jwk = { kty: 'EC', crv: 'P-256', d, x, y };
  return crypto.subtle.importKey('jwk', jwk, CURVE, false, ['deriveBits']);
}

/* The published answer, with WebCrypto alone: both sides reach `sharedBytes`, and HKDF with
   `info` turns it into `sessionBytes`. */
async function checkAnswer(a: Agreement, b64: AgreementImpl['b64']): Promise<string[]> {
  const found: string[] = [];
  const jwk: unknown = JSON.parse(b64.utf8String(b64.fromBase64Url(a.serverJwk)));
  const d = isRecord(jwk) && typeof jwk.d === 'string' ? jwk.d : '';
  const raw = (point: string) => b64.fromBase64Url(point);
  const [server, client, serverPublic, clientPublic] = await Promise.all([
    privateKey(b64, d, a.serverPublic),
    privateKey(b64, a.clientPrivate, a.clientPublic),
    crypto.subtle.importKey('raw', raw(a.serverPublic), CURVE, false, []),
    crypto.subtle.importKey('raw', raw(a.clientPublic), CURVE, false, []),
  ]);
  const secrets = await Promise.all([
    crypto.subtle.deriveBits({ name: 'ECDH', public: clientPublic }, server, 256),
    crypto.subtle.deriveBits({ name: 'ECDH', public: serverPublic }, client, 256),
  ]);
  const [fromServer, fromClient] = secrets.map((bits) => b64.toBase64Url(new Uint8Array(bits)));
  if (fromServer !== a.sharedBytes) {
    found.push(`agreement ${a.name}: the server side derives another secret`);
  }
  if (fromClient !== a.sharedBytes) {
    found.push(`agreement ${a.name}: the client side derives another secret`);
  }
  const secret = raw(a.sharedBytes);
  const material = await crypto.subtle.importKey('raw', secret, 'HKDF', false, ['deriveBits']);
  const info = b64.utf8Bytes(a.info);
  const hkdf = { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info };
  const key = b64.toBase64Url(new Uint8Array(await crypto.subtle.deriveBits(hkdf, material, 256)));
  if (key !== a.sessionBytes) {
    found.push(`agreement ${a.name}: HKDF with info "${a.info}" derives another key`);
  }
  return found;
}

/* This copy: its server key from the JWK, its AAD, and its session key from either side opening
   the envelope. A changed HKDF label or point encoding fails here. */
async function checkThisCopy(a: Agreement, impl: AgreementImpl): Promise<string[]> {
  const { aes, b64, ecdh, env } = impl;
  const found: string[] = [];
  const v = a.vector;
  const aad =
    v.kind === 'request'
      ? env.requestAad(v.method ?? '', v.pattern, v.kid, v.ts)
      : env.responseAad(v.status ?? 0, v.pattern, v.kid, v.ts);
  if (b64.utf8String(aad) !== v.aad) {
    found.push(`agreement ${a.name}: AAD "${b64.utf8String(aad)}" is not "${v.aad}"`);
  }
  const server = await ecdh.importServerKeyPair(a.serverJwk);
  if (server.publicKey !== a.serverPublic) {
    found.push(`agreement ${a.name}: the server key's public half is not serverPublic`);
  }
  const client = await privateKey(b64, a.clientPrivate, a.clientPublic);
  const sides: [string, CryptoKey, string][] = [
    ['the server side', server.privateKey, a.clientPublic],
    ['the client side', client, a.serverPublic],
  ];
  const opened = await Promise.all(
    sides.map(async ([side, mine, theirs]) => {
      try {
        const key = await ecdh.deriveSessionKey(mine, theirs);
        const plain = await aes.open(key, b64.fromBase64Url(v.iv), b64.fromBase64Url(v.ct), aad);
        const body = JSON.stringify(JSON.parse(b64.utf8String(plain)));
        if (body === JSON.stringify(v.plaintext)) return [];
        return [`agreement ${a.name}: ${side} opened the envelope to another body`];
      } catch (error) {
        return [`agreement ${a.name}: ${side}'s key does not open the envelope (${reason(error)})`];
      }
    }),
  );
  return [...found, ...opened.flat()];
}

/* A refused point must carry the vector's code: refusing it for another reason is drift too. */
async function checkPoint(r: PointReject, impl: AgreementImpl, mine: CryptoKey): Promise<string[]> {
  try {
    await impl.ecdh.deriveSessionKey(mine, r.point);
    return [`point reject ${r.name}: accepted, but it must be refused with ${r.code}`];
  } catch (error) {
    const code = isRecord(error) ? error.code : undefined;
    if (code === r.code) return [];
    return [`point reject ${r.name}: refused with ${String(code)}, not ${r.code}`];
  }
}

/** Lib: checkAgreements
 * Runs the vectors' `agreements` and `pointRejects` through WebCrypto and through this copy, and
 * returns every problem found; a file without them is a problem of its own. `pointRejects` bind a
 * server only: it imports the peer point a client sends, while a public client imports the key the
 * server's own handshake returned.
 */
export async function checkAgreements(
  file: { agreements?: Agreement[]; pointRejects?: PointReject[] },
  impl: AgreementImpl,
  side: 'server' | 'client' = 'server',
): Promise<AgreementReport> {
  const agreements = file.agreements ?? [];
  const points = side === 'server' ? (file.pointRejects ?? []) : [];
  if (agreements.length === 0 || (side === 'server' && points.length === 0)) {
    const missing = 'the vectors carry no `agreements` or no `pointRejects`; sync them';
    return { problems: [missing], agreements: 0, points: 0 };
  }
  const mine = await impl.ecdh.generateEphemeralKeyPair();
  const results = await Promise.all([
    ...agreements.map(async (a) => {
      try {
        return [...(await checkAnswer(a, impl.b64)), ...(await checkThisCopy(a, impl))];
      } catch (error) {
        return [`agreement ${a.name}: could not be checked (${reason(error)})`];
      }
    }),
    ...points.map((r) => checkPoint(r, impl, mine.privateKey)),
  ]);
  return { problems: results.flat(), agreements: agreements.length, points: points.length };
}
