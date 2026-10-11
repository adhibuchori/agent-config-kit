/* Unit tests for the payload refusal: part of the payload contract (.claude/PAYLOAD-CONTRACT.md). */
import { describe, expect, test } from 'bun:test';
import { PAYLOAD_CODES } from '../errors';
import { checkProblemTypeBase, PAYLOAD_TITLES, payloadRefusal } from '../refusal';

/* The kit's placeholder base; a real API sets its own (.claude/rules/common/error-codes.md). */
const BASE = 'https://example.invalid/problems/';

describe('payloadRefusal', () => {
  test('mints the type from the base and the code, with a fixed title and no detail', async () => {
    const response = payloadRefusal(BASE, 400, 'ENVELOPE_REQUIRED');
    expect(response.status).toBe(400);
    expect(response.headers.get('content-type')).toBe('application/problem+json');
    expect(await response.json()).toEqual({
      type: 'https://example.invalid/problems/ENVELOPE_REQUIRED',
      title: 'Sealed body required',
      status: 400,
      code: 'ENVELOPE_REQUIRED',
    });
  });

  test('carries the request id when there is one', async () => {
    const response = payloadRefusal(BASE, 500, 'ENVELOPE_MALFORMED', 'req-1');
    expect(await response.json()).toEqual({
      type: 'https://example.invalid/problems/ENVELOPE_MALFORMED',
      title: 'Malformed envelope',
      status: 500,
      code: 'ENVELOPE_MALFORMED',
      requestId: 'req-1',
    });
  });

  test('titles every code, each differently', () => {
    expect(Object.keys(PAYLOAD_TITLES).toSorted()).toEqual(PAYLOAD_CODES.toSorted());
    expect(new Set(Object.values(PAYLOAD_TITLES)).size).toBe(PAYLOAD_CODES.length);
  });
});

describe('checkProblemTypeBase', () => {
  test('passes an absolute https base that ends in a slash', () => {
    expect(checkProblemTypeBase(BASE)).toBe(BASE);
    const real = 'https://api.example.com/problems/';
    expect(checkProblemTypeBase(real)).toBe(real);
  });

  test('throws, saying why, on any other base', () => {
    const refused: [string, string][] = [
      ['/problems/', 'is not an absolute URI'],
      ['http://example.invalid/problems/', 'is not https'],
      ['https://example.invalid/problems/?v=1', 'carries a query or a fragment'],
      ['https://example.invalid/problems/#x', 'carries a query or a fragment'],
      ['https://example.invalid/problems', 'does not end in /'],
      ['https://Example.invalid/problems/', 'is not written as https://example.invalid/problems/'],
    ];
    for (const [base, why] of refused) {
      expect(() => checkProblemTypeBase(base)).toThrow(`problemTypeBase "${base}" ${why}`);
    }
  });
});
