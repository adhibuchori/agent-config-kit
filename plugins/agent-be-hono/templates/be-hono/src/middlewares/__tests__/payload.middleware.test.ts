/* Unit tests for the Hono payload middleware: part of the payload contract (.claude/PAYLOAD-CONTRACT.md). */
import { describe, expect, test } from 'bun:test';
import { Hono } from 'hono';
import { toBase64Url } from '../../lib/payload/base64url';
import { openJson, parseEnvelope, sealJson } from '../../lib/payload/codec';
import {
  deriveSessionKey,
  generateEphemeralKeyPair,
  generateServerKeyJwk,
  importServerKeyPair,
} from '../../lib/payload/ecdh';
import {
  ENCRYPTED_MEDIA_TYPE,
  EPK_HEADER,
  KID_HEADER,
  requestAad,
  responseAad,
} from '../../lib/payload/envelope';
import { createKeyRing, type KeyRing } from '../../lib/payload/key-ring';
import type { EndpointMap } from '../../lib/payload/policy';
import { createPayloadMiddleware, type PayloadMiddlewareOptions } from '../payload.middleware';

/**
 * Through the real cipher and a real Hono app: a double that accepts what the real transport
 * refuses would prove nothing about the contract.
 */

const registry: EndpointMap = {
  POST_NOTES: { method: 'POST', pattern: '/api/notes', encryption: 'strict' },
  GET_NOTES_BY_ID: { method: 'GET', pattern: '/api/notes/:id', encryption: 'strict' },
  DELETE_NOTES_BY_ID: { method: 'DELETE', pattern: '/api/notes/:id', encryption: 'strict' },
  POST_UPLOAD: {
    method: 'POST',
    pattern: '/api/upload',
    encryption: 'response-only',
    reason: 'multipart',
  },
  GET_STREAM: {
    method: 'GET',
    pattern: '/api/stream',
    encryption: 'request-only',
    reason: 'event stream',
  },
  GET_HEALTH: { method: 'GET', pattern: '/health', encryption: 'none', reason: 'probe' },
  GET_TEXT: { method: 'GET', pattern: '/api/text', encryption: 'strict' },
  GET_EMPTY: { method: 'GET', pattern: '/api/empty', encryption: 'strict' },
};

/* Test-only key material: 32 bytes of one value, never a real key. */
const ring: KeyRing = await createKeyRing([
  { value: `k1:${toBase64Url(new Uint8Array(32).fill(5))}`, name: 'TEST_KEY' },
]);
const server = await importServerKeyPair(await generateServerKeyJwk());

function app(options: Partial<PayloadMiddlewareOptions> = {}): Hono {
  const hono = new Hono();
  hono.use(
    createPayloadMiddleware({
      mode: 'strict',
      registry,
      keyRing: async () => ring,
      browserKeyPair: async () => server,
      ...options,
    }),
  );
  hono.post('/api/notes', async (c) => c.json({ received: await c.req.json() }, 201));
  hono.get('/api/notes/:id', (c) => c.json({ id: c.req.param('id') }));
  hono.delete('/api/notes/:id', (c) => c.body(null, 204));
  hono.post('/api/upload', async (c) => c.json({ size: (await c.req.text()).length }));
  hono.get('/api/stream', (c) => c.text('data: 1\n\n'));
  hono.get('/health', (c) => c.json({ ok: true }));
  hono.get('/api/text', (c) => c.text('not json'));
  hono.get('/api/empty', (c) => c.body(null, 200));
  hono.get('/unregistered', (c) => c.json({ open: true }));
  hono.onError((error, c) => c.json({ error: error.message }, 500));
  return hono;
}

const aadFor = (method: string, pattern: string) => (kid: string, ts: number) =>
  requestAad(method, pattern, kid, ts);

async function sealed(body: unknown, pattern = '/api/notes'): Promise<string> {
  return JSON.stringify(
    await sealJson(body, { key: ring.primary.key, kid: 'k1', aadFor: aadFor('POST', pattern) }),
  );
}

async function opened(response: Response, pattern: string): Promise<unknown> {
  expect(response.headers.get('content-type')).toBe(ENCRYPTED_MEDIA_TYPE);
  const envelope = parseEnvelope(await response.text());
  return openJson(envelope, {
    key: ring.resolve(envelope.kid),
    aadFor: (kid, ts) => responseAad(response.status, pattern, kid, ts),
  });
}

describe('payload middleware, server callers', () => {
  test('opens a sealed request and seals the answer under the same key', async () => {
    const response = await app().request('/api/notes', {
      method: 'POST',
      headers: { 'content-type': ENCRYPTED_MEDIA_TYPE, [KID_HEADER]: 'k1' },
      body: await sealed({ title: 'x' }),
    });
    expect(response.status).toBe(201);
    expect(await opened(response, '/api/notes')).toEqual({ received: { title: 'x' } });
  });

  test('refuses a plaintext body on a sealed route, in plaintext', async () => {
    const response = await app().request('/api/notes', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"title":"x"}',
    });
    expect(response.status).toBe(400);
    expect(response.headers.get('content-type')).toBe('application/problem+json');
    expect(await response.json()).toMatchObject({ code: 'ENVELOPE_REQUIRED' });
  });

  test('seals a bodiless GET under the key its header names, or the primary', async () => {
    const named = await app().request('/api/notes/7', { headers: { [KID_HEADER]: 'k1' } });
    expect(await opened(named, '/api/notes/:id')).toEqual({ id: '7' });
    const defaulted = await app().request('/api/notes/8');
    expect(await opened(defaulted, '/api/notes/:id')).toEqual({ id: '8' });
  });

  test('refuses a key id it does not hold', async () => {
    const response = await app().request('/api/notes/7', { headers: { [KID_HEADER]: 'k9' } });
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ code: 'ENVELOPE_KEY_UNKNOWN' });
  });

  test('lets a bodiless DELETE through and leaves a 204 alone', async () => {
    const response = await app().request('/api/notes/7', { method: 'DELETE' });
    expect(response.status).toBe(204);
  });

  test('takes a plain multipart upload on a response-only route and seals the answer', async () => {
    const form = new FormData();
    form.set('file', new Blob(['abc']), 'a.txt');
    const response = await app().request('/api/upload', { method: 'POST', body: form });
    expect(await opened(response, '/api/upload')).toMatchObject({ size: expect.any(Number) });
  });

  test('leaves a request-only stream and a none route in plaintext', async () => {
    expect(await (await app().request('/api/stream')).text()).toBe('data: 1\n\n');
    expect(await (await app().request('/health')).json()).toEqual({ ok: true });
  });

  test('passes an unregistered route through, and everything when switched off', async () => {
    expect(await (await app().request('/unregistered')).json()).toEqual({ open: true });
    const off = await app({ mode: 'off' }).request('/api/notes/7');
    expect(await off.json()).toEqual({ id: '7' });
  });

  test('refuses to seal a body that is not JSON, and skips an empty one', async () => {
    const text = await app().request('/api/text');
    expect(text.status).toBe(500);
    expect(await text.json()).toMatchObject({ code: 'ENVELOPE_MALFORMED' });
    const empty = await app().request('/api/empty');
    expect(empty.status).toBe(200);
    expect(await empty.text()).toBe('');
  });

  test('uses the refusal the app supplies', async () => {
    const custom = app({ refuse: (c, _status, error) => c.json({ custom: error.code }, 422) });
    const response = await custom.request('/api/notes/7', { headers: { [KID_HEADER]: 'k9' } });
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ custom: 'ENVELOPE_KEY_UNKNOWN' });
  });

  test('lets an error that is not a payload failure reach the app', async () => {
    const broken = app({
      keyRing: async () => {
        throw new Error('vault down');
      },
    });
    const response = await broken.request('/api/notes/7');
    expect(await response.json()).toEqual({ error: 'vault down' });
  });
});

describe('payload middleware, browser callers', () => {
  test('agrees a key from the ephemeral header and seals the answer with it', async () => {
    const browser = await generateEphemeralKeyPair();
    const key = await deriveSessionKey(browser.privateKey, server.publicKey);
    const body = JSON.stringify(
      await sealJson({ title: 'y' }, { key, kid: 'ecdh', aadFor: aadFor('POST', '/api/notes') }),
    );
    const response = await app().request('/api/notes', {
      method: 'POST',
      headers: { 'content-type': ENCRYPTED_MEDIA_TYPE, [EPK_HEADER]: browser.publicKey },
      body,
    });
    const envelope = parseEnvelope(await response.text());
    expect(envelope.kid).toBe('ecdh');
    const answer = await openJson(envelope, {
      key,
      aadFor: (kid, ts) => responseAad(201, '/api/notes', kid, ts),
    });
    expect(answer).toEqual({ received: { title: 'y' } });
  });

  test('refuses a browser key where the service agrees none, and a missing one where it has no ring', async () => {
    const browser = await generateEphemeralKeyPair();
    const noBrowser = await app({ browserKeyPair: undefined }).request('/api/notes/1', {
      headers: { [EPK_HEADER]: browser.publicKey },
    });
    expect(await noBrowser.json()).toMatchObject({ code: 'ENVELOPE_KEY_UNKNOWN' });
    const noRing = await app({ keyRing: undefined }).request('/api/notes/1');
    expect(await noRing.json()).toMatchObject({ code: 'ENVELOPE_REQUIRED' });
  });
});
