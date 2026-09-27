/**
 * Every route this service serves, and what happens to its payload (.claude/PAYLOAD-CONTRACT.md).
 *
 * The routes the OpenAPI document declares arrive generated, with their policies decided in
 * payload.config.json. Only routes served outside the document are written here, each with its
 * policy and, when it is not `strict`, the reason. The payload middleware refuses nothing it
 * cannot find here, so a route missing from this file is a route nobody decided a policy for:
 * `check:endpoints` keeps the generated half equal to the spec.
 */

import type { EndpointMap, PrefixRule } from '../payload/policy';
import { GENERATED_ENDPOINTS } from './endpoints.generated';

/** Routes mounted outside the OpenAPI document. */
const LOCAL_ENDPOINTS = {
  GET_OPENAPI_JSON: {
    method: 'GET',
    pattern: '/openapi.json',
    encryption: 'none',
    reason: 'the specification itself; client generators read it with no key',
  },
} as const satisfies EndpointMap;

/** The whole registry. */
export const ENDPOINTS = {
  ...GENERATED_ENDPOINTS,
  ...LOCAL_ENDPOINTS,
} as const satisfies EndpointMap;

/**
 * Policies for route families that cannot be enumerated. An auth library mounted on a catch-all
 * decides its own route list through its plugins; a prefix covers the routes a future upgrade
 * adds, which an enumeration would silently leave without a policy.
 */
export const ENDPOINT_PREFIXES: readonly PrefixRule[] = [
  {
    prefix: '/api/auth/',
    encryption: 'strict',
    reason: 'the auth library owns its route list; a prefix covers routes an upgrade adds',
  },
];
