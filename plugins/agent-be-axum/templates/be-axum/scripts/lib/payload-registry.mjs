/**
 * The payload registry's shared half for the Go, Rust and Swift stacks. It reads and validates
 * payload.config.json, derives the endpoints an OpenAPI document implies, and emits the one file
 * each language compiles them from (.claude/PAYLOAD-CONTRACT.md).
 *
 * Shared by scripts/generate/payload-registry.mjs, which writes that file, and
 * scripts/check/payload-registry.mjs, which emits it again in memory and compares the bytes. One
 * derivation for both, and the same one as the TypeScript stacks' deriveEndpoints, so every repo
 * that speaks the contract binds the same route pattern into its AAD. The emitted layout is the one
 * gofmt, rustfmt and swift-format leave as it is, so a format gate never fights the generator.
 *
 * Plain Node ESM, no dependencies, the same bytes in every stack that ships it.
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export const CONFIG_FILE = 'payload.config.json';

/** The five refusal codes; the spec's Problem.code lists every one of them. */
export const ENVELOPE_CODES = [
  'ENVELOPE_REQUIRED',
  'ENVELOPE_MALFORMED',
  'ENVELOPE_EXPIRED',
  'ENVELOPE_KEY_UNKNOWN',
  'ENVELOPE_REJECTED',
];

const KEYS = ['encryption', 'spec', 'registry', 'language', 'handshake', 'exemptions', 'peers'];
const EXTENSIONS = { go: '.go', rust: '.rs', swift: '.swift' };
const POLICIES = new Set(['strict', 'response-only', 'request-only', 'none']);
const METHODS = new Map(
  ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'].map((m) => [m.toLowerCase(), m]),
);
const EXEMPTION_KEY = /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \/\S*$/;
const MAX_WIDTH = 120;

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function invalid(message) {
  return new Error(`${CONFIG_FILE}: ${message}`);
}

function nonEmpty(value) {
  return typeof value === 'string' && value.trim() !== '';
}

/** `{ "METHOD /pattern": { encryption, reason } }`, as the TypeScript stacks write it. */
function exemptionsOf(value) {
  if (value === undefined) return {};
  if (!isRecord(value)) throw invalid('exemptions must be an object');
  const out = {};
  for (const [route, entry] of Object.entries(value)) {
    if (!EXEMPTION_KEY.test(route)) {
      throw invalid(`exemption "${route}" must read "METHOD /pattern"`);
    }
    const policy = isRecord(entry) ? entry.encryption : undefined;
    if (!POLICIES.has(policy) || policy === 'strict') {
      throw invalid(`exemption "${route}" needs an encryption other than strict`);
    }
    if (!nonEmpty(entry.reason)) throw invalid(`exemption "${route}" needs a written reason`);
    out[route] = { encryption: policy, reason: entry.reason };
  }
  return out;
}

function peersOf(value) {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw invalid('peers must be a list');
  return value.map((peer) => {
    if (!isRecord(peer) || !nonEmpty(peer.name) || !nonEmpty(peer.root)) {
      throw invalid('each peer needs a name and a root');
    }
    return { name: peer.name, root: peer.root };
  });
}

function readJson(path, what) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (err) {
    throw new Error(`${what} is not readable JSON (${err.message})`, { cause: err });
  }
}

/** Lib: readPayloadConfig
 * payload.config.json at `root`, validated, or null where the contract is not adopted. Only
 * `strict` and `off` are a switch: a typo fails here instead of reading as either.
 */
export function readPayloadConfig(root) {
  const path = join(root, CONFIG_FILE);
  if (!existsSync(path)) return null;
  const raw = readJson(path, CONFIG_FILE);
  if (!isRecord(raw)) throw invalid('must hold a JSON object');
  const unknown = Object.keys(raw).filter((key) => !KEYS.includes(key));
  if (unknown.length > 0) {
    throw invalid(`unknown key "${unknown[0]}"; the keys are ${KEYS.join(', ')}`);
  }
  if (raw.encryption !== 'strict' && raw.encryption !== 'off') {
    const was = raw.encryption === undefined ? 'missing' : JSON.stringify(raw.encryption);
    throw invalid(`encryption must be "strict" or "off", not ${was}`);
  }
  if (!Object.hasOwn(EXTENSIONS, raw.language)) {
    throw invalid(`language must be "go", "rust" or "swift", not ${JSON.stringify(raw.language)}`);
  }
  if (!nonEmpty(raw.spec) || !raw.spec.endsWith('.json')) {
    throw invalid('spec must name the OpenAPI document, a .json file');
  }
  const extension = EXTENSIONS[raw.language];
  if (!nonEmpty(raw.registry) || !raw.registry.endsWith(extension)) {
    throw invalid(`registry must name the generated ${extension} file`);
  }
  if (raw.handshake !== undefined && !nonEmpty(raw.handshake)) {
    throw invalid('handshake must name an operationId');
  }
  return {
    encryption: raw.encryption,
    spec: raw.spec,
    registry: raw.registry,
    language: raw.language,
    handshake: raw.handshake ?? null,
    exemptions: exemptionsOf(raw.exemptions),
    peers: peersOf(raw.peers),
  };
}

/** Lib: readPeerConfig
 * A peer's spec path and exemptions, from any stack that speaks the contract (a TypeScript peer
 * writes other keys, and its spec defaults to openapi.json), or null where none is checked out.
 */
export function readPeerConfig(root) {
  const path = join(root, CONFIG_FILE);
  if (!existsSync(path)) return null;
  const raw = readJson(path, path);
  if (!isRecord(raw)) throw invalid('must hold a JSON object');
  return {
    spec: nonEmpty(raw.spec) ? raw.spec : 'openapi.json',
    exemptions: exemptionsOf(raw.exemptions),
  };
}

/** Lib: readSpec
 * The OpenAPI document the config names, parsed.
 */
export function readSpec(root, config) {
  const path = join(root, config.spec);
  if (!existsSync(path)) {
    throw new Error(
      `${config.spec} not found: export the spec (a backend) or copy the backend's (an app)`,
    );
  }
  return readJson(path, config.spec);
}

function byMethodThenPattern(a, b) {
  if (a.method !== b.method) return a.method < b.method ? -1 : 1;
  if (a.pattern !== b.pattern) return a.pattern < b.pattern ? -1 : 1;
  return 0;
}

/** Lib: deriveEndpoints
 * Every operation in the spec, `{x}` as `:x` in its pattern, `strict` unless an exemption says
 * otherwise, sorted by method then pattern. The operation ID is the spec's `operationId`, else the
 * one swift-openapi-generator falls back to: the lower-case method and the path.
 */
export function deriveEndpoints(spec, exemptions) {
  const out = [];
  const paths = isRecord(spec) && isRecord(spec.paths) ? spec.paths : {};
  for (const [route, operations] of Object.entries(paths)) {
    if (!isRecord(operations)) continue;
    for (const [key, operation] of Object.entries(operations)) {
      const method = METHODS.get(key.toLowerCase());
      if (!method) continue;
      const pattern = route.replace(/\{([^}]+)\}/g, ':$1');
      const exemption = exemptions[`${method} ${pattern}`];
      const id = isRecord(operation) ? operation.operationId : undefined;
      out.push({
        method,
        route,
        pattern,
        policy: exemption?.encryption ?? 'strict',
        reason: exemption?.reason ?? '',
        operationId: nonEmpty(id) ? id : `${method.toLowerCase()}${route}`,
      });
    }
  }
  return out.sort(byMethodThenPattern);
}

/** Lib: problemCodes
 * The spec's `Problem.code` enum (inline, or one `$ref` away), or null when it has none.
 */
export function problemCodes(spec) {
  const schemas = isRecord(spec) && isRecord(spec.components) ? spec.components.schemas : null;
  const resolve = (node) => {
    const ref = isRecord(node) && typeof node.$ref === 'string' ? node.$ref : '';
    const name = ref.startsWith('#/components/schemas/') ? ref.slice(21) : null;
    return name && isRecord(schemas) ? schemas[name] : node;
  };
  const problem = resolve(isRecord(schemas) ? schemas.Problem : null);
  const code = resolve(
    isRecord(problem) && isRecord(problem.properties) ? problem.properties.code : null,
  );
  return isRecord(code) && Array.isArray(code.enum) ? code.enum : null;
}

/** Lib: sortKeys
 * A JSON value with every object's keys sorted, so two documents compare by meaning.
 */
export function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (!isRecord(value)) return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortKeys(value[key])]),
  );
}

/* A double-quoted literal for all three languages: `\` and `"` escaped, control characters as a
   Unicode escape in the language's own spelling. */
function literal(value, escape) {
  let out = '"';
  for (const ch of value) {
    const code = ch.codePointAt(0) ?? 0;
    if (ch === '\\' || ch === '"') out += `\\${ch}`;
    else if (code < 0x20 || code === 0x7f || code === 0xfeff) out += escape(code.toString(16));
    else out += ch;
  }
  return `${out}"`;
}
const goString = (value) => literal(value, (hex) => `\\u${hex.padStart(4, '0')}`);
const braceString = (value) => literal(value, (hex) => `\\u{${hex}}`);

/* Columns as an editor shows them, a tab as four. */
const width = (line) => [...line.replaceAll('\t', '    ')].length;

const GO_POLICY = {
  strict: 'PolicyStrict',
  'response-only': 'PolicyResponseOnly',
  'request-only': 'PolicyRequestOnly',
  none: 'PolicyNone',
};

/* One line per entry; an entry too wide for one goes over seven, aligned the way gofmt aligns. */
function goEntry(e) {
  const fields = [
    ['Method', goString(e.method)],
    ['Route', goString(e.route)],
    ['Pattern', goString(e.pattern)],
    ['Policy', GO_POLICY[e.policy]],
    ['Reason', goString(e.reason)],
  ];
  const line = `\t{${fields.map(([key, value]) => `${key}: ${value}`).join(', ')}},`;
  if (width(line) <= MAX_WIDTH) return [line];
  return ['\t{', ...fields.map(([key, value]) => `\t\t${`${key}:`.padEnd(9)}${value},`), '\t},'];
}

function emitGo(config, endpoints) {
  const registry =
    endpoints.length === 0
      ? ['var registry = []Endpoint{}']
      : ['var registry = []Endpoint{', ...endpoints.flatMap(goEntry), '}'];
  return [
    '// Code generated by scripts/generate/payload-registry.mjs. DO NOT EDIT.',
    '',
    'package payload',
    '',
    `const configMode = ${goString(config.encryption)}`,
    '',
    ...registry,
  ];
}

const RUST_POLICY = {
  strict: 'Policy::Strict',
  'response-only': 'Policy::ResponseOnly',
  'request-only': 'Policy::RequestOnly',
  none: 'Policy::None',
};

function rustFields(e, indent) {
  return [
    `method: ${braceString(e.method)}`,
    `route: ${braceString(e.route)}`,
    `pattern: ${braceString(e.pattern)}`,
    `policy: ${RUST_POLICY[e.policy]}`,
    `reason: ${braceString(e.reason)}`,
  ].map((field) => `${indent}${field},`);
}

/* rustfmt lays a struct literal out vertically past a few columns, and hugs a lone element. */
function emitRust(config, endpoints) {
  const head = 'pub(crate) const ENDPOINTS: &[Endpoint] = &[';
  let list;
  if (endpoints.length === 0) list = [`${head}];`];
  else if (endpoints.length === 1) {
    list = [`${head}Endpoint {`, ...rustFields(endpoints[0], '    '), '}];'];
  } else {
    const entries = endpoints.flatMap((e) => [
      '    Endpoint {',
      ...rustFields(e, '        '),
      '    },',
    ]);
    list = [head, ...entries, '];'];
  }
  return [
    '// @generated by scripts/generate/payload-registry.mjs. Do not edit.',
    '',
    endpoints.length === 0
      ? 'use super::policy::Endpoint;'
      : 'use super::policy::{Endpoint, Policy};',
    '',
    `pub(crate) const CONFIG_MODE: &str = ${braceString(config.encryption)};`,
    '',
    ...list,
  ];
}

const SWIFT_POLICY = {
  strict: '.strict',
  'response-only': '.responseOnly',
  'request-only': '.requestOnly',
  none: '.none',
};

/* `<prefix>PayloadEndpoint(...)<suffix>` on one line when it fits; otherwise the arguments go on
   the lines below, filled the way swift-format fills them. */
function swiftValue(prefix, e, suffix) {
  const args = [
    `method: ${braceString(e.method)}`,
    `pattern: ${braceString(e.pattern)}`,
    `policy: ${SWIFT_POLICY[e.policy]}`,
  ];
  const line = `${prefix}PayloadEndpoint(${args.join(', ')})${suffix}`;
  if (width(line) <= MAX_WIDTH) return [line];
  const indent = `${' '.repeat(prefix.length - prefix.trimStart().length)}    `;
  const chunks = args.map((arg, i) => (i < args.length - 1 ? `${arg},` : `${arg})${suffix}`));
  const lines = [`${prefix}PayloadEndpoint(`];
  let current = `${indent}${chunks[0]}`;
  for (const chunk of chunks.slice(1)) {
    if (width(current) + 1 + width(chunk) <= MAX_WIDTH) current += ` ${chunk}`;
    else {
      lines.push(current);
      current = `${indent}${chunk}`;
    }
  }
  return [...lines, current];
}

function emitSwift(config, endpoints) {
  const seen = new Map();
  for (const e of endpoints) {
    const other = seen.get(e.operationId);
    if (other) {
      throw new Error(
        `${config.spec}: operationId "${e.operationId}" names both ${other} and ${e.method} ${e.route}`,
      );
    }
    seen.set(e.operationId, `${e.method} ${e.route}`);
  }
  const shake = endpoints.find((e) => e.operationId === config.handshake);
  const handshake = '    static let handshake: PayloadEndpoint? = ';
  const head = '    static let entries: [String: PayloadEndpoint] = [';
  const suffix = endpoints.length === 1 ? '' : ',';
  const entries =
    endpoints.length === 0
      ? [`${head.slice(0, -1)}[:]`]
      : [
          head,
          ...endpoints.flatMap((e) =>
            swiftValue(`        ${braceString(e.operationId)}: `, e, suffix),
          ),
          '    ]',
        ];
  return [
    '// Generated by scripts/generate/payload-registry.mjs. Do not edit.',
    '',
    'enum PayloadEndpoints {',
    `    static let configMode = ${braceString(config.encryption)}`,
    ...(shake ? swiftValue(handshake, shake, '') : [`${handshake}nil`]),
    ...entries,
    '}',
  ];
}

const EMITTERS = { go: emitGo, rust: emitRust, swift: emitSwift };

/** Lib: emitRegistry
 * The registry file for the config's language, byte for byte what the generator writes.
 */
export function emitRegistry(config, endpoints) {
  return `${EMITTERS[config.language](config, endpoints).join('\n')}\n`;
}
