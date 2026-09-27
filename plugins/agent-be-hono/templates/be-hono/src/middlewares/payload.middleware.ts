/**
 * The payload contract at this service's edge (.claude/PAYLOAD-CONTRACT.md).
 *
 * Opens every sealed request body before any validator runs and seals every response the registry
 * says to seal, so no handler, service or schema ever sees an envelope. Mount it after the cheap
 * refusals (body limit, rate limit, timeout), so an oversized or throttled request is refused
 * before anything is decrypted, and before every route. A route the registry does not describe is
 * passed through: the router answers it with a 404 and there is no payload to protect;
 * `check:endpoints` is what keeps every real route in the registry.
 *
 * A refusal raised here leaves in plaintext problem+json, with a code and never a payload: the
 * caller may hold no working key, and a refusal it cannot read is one it simply retries.
 */

import type { Context, MiddlewareHandler } from 'hono';
import { createMiddleware } from 'hono/factory';
import { openJson, parseEnvelope, sealJson } from '../lib/payload/codec';
import { deriveSessionKey, ECDH_KID, type EcdhKeyPair } from '../lib/payload/ecdh';
import {
  ENCRYPTED_MEDIA_TYPE,
  EPK_HEADER,
  KID_HEADER,
  requestAad,
  responseAad,
} from '../lib/payload/envelope';
import { isPayloadError, PayloadError } from '../lib/payload/errors';
import type { KeyRing } from '../lib/payload/key-ring';
import type { EncryptionMode } from '../lib/payload/mode';
import {
  matchEndpoint,
  sealsRequest,
  sealsResponse,
  type EndpointMap,
  type EndpointMatch,
  type PrefixRule,
} from '../lib/payload/policy';

/** What the middleware needs; resolve every value once, at startup. */
export interface PayloadMiddlewareOptions {
  /** From `resolveEncryptionMode`. `off` passes everything through. */
  mode: EncryptionMode;
  /** The registry this service serves. */
  registry: EndpointMap;
  /** Route families that cannot be enumerated, such as an auth library's catch-all. */
  prefixes?: readonly PrefixRule[];
  /** Pre-shared keys for server callers (a frontend's server, another service). */
  keyRing?: () => Promise<KeyRing>;
  /** This service's ECDH keypair, when browsers call it directly with an ephemeral key. */
  browserKeyPair?: () => Promise<EcdhKeyPair>;
  /** Builds the plaintext refusal; defaults to RFC 9457 problem+json with the code. */
  refuse?: (c: Context, status: number, error: PayloadError) => Response;
}

/** The key one exchange uses in both directions, and the kid its response carries. */
interface ExchangeKey {
  key: (kid: string) => CryptoKey;
  responseKid: string;
}

function problem(_c: Context, status: number, error: PayloadError): Response {
  const body = {
    type: 'about:blank',
    title: 'Payload refused',
    status,
    detail: error.message,
    code: error.code,
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/problem+json' },
  });
}

async function exchangeKey(c: Context, options: PayloadMiddlewareOptions): Promise<ExchangeKey> {
  const epk = c.req.header(EPK_HEADER);
  if (epk) {
    if (!options.browserKeyPair) {
      throw new PayloadError('ENVELOPE_KEY_UNKNOWN', 'This service agrees no keys with browsers');
    }
    const { privateKey } = await options.browserKeyPair();
    const agreed = await deriveSessionKey(privateKey, epk);
    return { key: () => agreed, responseKid: ECDH_KID };
  }
  if (!options.keyRing) {
    const reason = `A sealed route needs the ${EPK_HEADER} header`;
    throw new PayloadError('ENVELOPE_REQUIRED', reason);
  }
  const ring = await options.keyRing();
  const responseKid = c.req.header(KID_HEADER) ?? ring.primary.kid;
  ring.resolve(responseKid);
  return { key: (kid) => ring.resolve(kid), responseKid };
}

/* Read from `c.req.raw`, never `c.req.text()`: the latter fills Hono's body cache, and the
   validator downstream would then parse the cached ciphertext as the request's JSON. */
async function openRequest(c: Context, match: EndpointMatch, exchange: ExchangeKey): Promise<void> {
  const raw = await c.req.raw.text();
  const headers = new Headers(c.req.raw.headers);
  headers.delete('content-length');
  if (raw.length === 0) {
    /* A POST or DELETE may carry no body; the spent stream is replaced with an empty request. */
    c.req.raw = new Request(c.req.raw.url, { method: c.req.raw.method, headers });
    return;
  }
  if (!(c.req.header('content-type') ?? '').includes(ENCRYPTED_MEDIA_TYPE)) {
    const route = `${match.method} ${match.pattern}`;
    throw new PayloadError('ENVELOPE_REQUIRED', `${route} takes a sealed body`);
  }
  const envelope = parseEnvelope(raw);
  const body = await openJson(envelope, {
    key: exchange.key(envelope.kid),
    aadFor: (kid, ts) => requestAad(match.method, match.pattern, kid, ts),
  });
  headers.set('content-type', 'application/json');
  /* Rebuilt from the URL: the original body is spent, and reusing the request as a template
     throws on some runtimes. Only a method that carries a body reaches this line. */
  const init: RequestInit = { method: c.req.raw.method, headers, body: JSON.stringify(body) };
  c.req.raw = new Request(c.req.raw.url, init);
}

async function sealResponse(
  c: Context,
  match: EndpointMatch,
  exchange: ExchangeKey,
): Promise<Response> {
  const status = c.res.status;
  let parsed: unknown;
  try {
    parsed = JSON.parse(await c.res.text());
  } catch {
    const reason = `${match.pattern} answered with a body that is not JSON`;
    throw new PayloadError('ENVELOPE_MALFORMED', reason);
  }
  const envelope = await sealJson(parsed, {
    key: exchange.key(exchange.responseKid),
    kid: exchange.responseKid,
    aadFor: (kid, ts) => responseAad(status, match.pattern, kid, ts),
  });
  const headers = new Headers(c.res.headers);
  headers.set('content-type', ENCRYPTED_MEDIA_TYPE);
  headers.delete('content-length');
  return new Response(JSON.stringify(envelope), { status, headers });
}

type Refuse = (c: Context, status: number, error: PayloadError) => Response;

/* The keys for this exchange and the request opened when it carries a sealed body, or the
   plaintext refusal to answer with instead. */
async function prepare(
  c: Context,
  match: EndpointMatch,
  options: PayloadMiddlewareOptions,
  opensRequest: boolean,
  refuse: Refuse,
): Promise<ExchangeKey | Response> {
  try {
    const exchange = await exchangeKey(c, options);
    if (opensRequest) await openRequest(c, match, exchange);
    return exchange;
  } catch (error) {
    if (!isPayloadError(error)) throw error;
    return refuse(c, 400, error);
  }
}

/** Lib: createPayloadMiddleware
 * The Hono middleware that enforces the payload contract for the registry it is given.
 */
export function createPayloadMiddleware(options: PayloadMiddlewareOptions): MiddlewareHandler {
  const refuse = options.refuse ?? problem;
  return createMiddleware(async (c, next) => {
    const path = new URL(c.req.url).pathname;
    const match = matchEndpoint(options.registry, options.prefixes ?? [], c.req.method, path);
    if (!match || options.mode === 'off') return next();
    const hasBody = c.req.method !== 'GET' && c.req.method !== 'HEAD';
    const opensRequest = sealsRequest(match.encryption) && hasBody;
    const sealsAnswer = sealsResponse(match.encryption);
    if (!opensRequest && !sealsAnswer) return next();

    const prepared = await prepare(c, match, options, opensRequest, refuse);
    if (prepared instanceof Response) return prepared;
    await next();
    if (!sealsAnswer || c.res.status === 204 || c.res.status === 304 || !c.res.body) return;
    try {
      c.res = await sealResponse(c, match, prepared);
    } catch (error) {
      /* Sealing failed on our side, a body that is not JSON on a sealed route: the refusal goes
         out in clear, with the code and none of the body it could not seal. */
      const reason = isPayloadError(error)
        ? error
        : new PayloadError('ENVELOPE_MALFORMED', 'The response could not be sealed');
      c.res = refuse(c, 500, reason);
    }
  });
}
