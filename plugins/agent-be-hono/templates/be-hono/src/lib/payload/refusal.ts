/**
 * The plaintext answer to a payload failure: problem+json whose type is minted from the code.
 *
 * RFC 9457: `type` is this API's problem-type base plus the code, the identity a client resolves
 * the failure by, so it is never `about:blank`; `title` names the problem type and is the same for
 * every occurrence. There is no `detail`: the builder takes the code, never the error, because the
 * internal message names route patterns and server state and belongs in a log. No `hono` import,
 * so the builder runs anywhere a `Response` exists.
 */

import type { PayloadCode } from './errors';

/** One title per code: it names the problem type, never the occurrence. */
export const PAYLOAD_TITLES: Readonly<Record<PayloadCode, string>> = {
  ENVELOPE_REQUIRED: 'Sealed body required',
  ENVELOPE_MALFORMED: 'Malformed envelope',
  ENVELOPE_EXPIRED: 'Envelope expired',
  ENVELOPE_KEY_UNKNOWN: 'Unknown payload key',
  ENVELOPE_REJECTED: 'Envelope rejected',
};

/** A refusal's body, every member of it. */
interface PayloadProblem {
  type: string;
  title: string;
  status: number;
  code: PayloadCode;
  requestId?: string;
}

/* Why `base` cannot prefix a problem type, or undefined when it can. */
function baseError(base: string): string | undefined {
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    return 'is not an absolute URI';
  }
  if (url.protocol !== 'https:') return 'is not https';
  if (base.includes('?') || base.includes('#')) return 'carries a query or a fragment';
  if (!base.endsWith('/')) return 'does not end in /';
  if (url.href !== base) return `is not written as ${url.href}`;
  return undefined;
}

/** Lib: checkProblemTypeBase
 * `base` when it can prefix a problem type: an absolute https URI with no query or fragment, ending
 * in `/`, written exactly as a URL parser writes it back. Throws, saying why, on anything else.
 */
export function checkProblemTypeBase(base: string): string {
  const why = baseError(base);
  if (why) throw new Error(`problemTypeBase "${base}" ${why}`);
  return base;
}

/** Lib: payloadRefusal
 * The plaintext problem+json answer to a payload failure, with the request id when there is one.
 */
export function payloadRefusal(
  base: string,
  status: number,
  code: PayloadCode,
  requestId?: string,
): Response {
  const problem: PayloadProblem = {
    type: `${base}${code}`,
    title: PAYLOAD_TITLES[code],
    status,
    code,
  };
  const body = requestId === undefined ? problem : { ...problem, requestId };
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/problem+json' },
  });
}
