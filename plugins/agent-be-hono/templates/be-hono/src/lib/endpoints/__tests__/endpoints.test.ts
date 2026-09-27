/* Unit tests for the endpoint registry: part of the payload contract (.claude/PAYLOAD-CONTRACT.md). */
import { describe, expect, test } from 'bun:test';
import { matchEndpoint, type EndpointDefinition } from '../../payload/policy';
import { ENDPOINT_PREFIXES, ENDPOINTS } from '../endpoints';

describe('the endpoint registry', () => {
  test('every entry that is not strict says why, and no strict entry does', () => {
    /* Widened on purpose: a fresh registry holds one literal policy, and the check must still read. */
    const entries: readonly EndpointDefinition[] = Object.values(ENDPOINTS);
    for (const entry of entries) {
      const hasReason = entry.reason !== undefined && entry.reason.trim() !== '';
      expect(hasReason).toBe(entry.encryption !== 'strict');
    }
  });

  test('every prefix rule says why', () => {
    for (const rule of ENDPOINT_PREFIXES) expect(rule.reason.trim()).not.toBe('');
  });

  test('the spec itself stays readable, and the auth catch-all stays sealed', () => {
    expect(matchEndpoint(ENDPOINTS, ENDPOINT_PREFIXES, 'GET', '/openapi.json')?.encryption).toBe(
      'none',
    );
    expect(
      matchEndpoint(ENDPOINTS, ENDPOINT_PREFIXES, 'POST', '/api/auth/sign-in/email')?.encryption,
    ).toBe('strict');
  });
});
