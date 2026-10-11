#!/usr/bin/env bats
# One spec, one registry, in every stack: the TypeScript derivation (scripts/lib/openapi-endpoints.ts
# in be-hono and fe-nextjs) and the Node one the Go, Rust and Swift stacks share
# (scripts/lib/payload-registry.mjs) give the same methods, patterns, policies and reasons, so every
# repo binds the same route pattern into its AAD. The TypeScript side runs on Bun, or on Node with
# tests/helpers/ts-resolve.mjs where Bun is absent.

load helpers

setup() {
  if command -v bun >/dev/null 2>&1; then
    TS=(bun)
  elif node -e 'process.exit(process.features.typescript ? 0 : 1)' 2>/dev/null; then
    TS=(node --no-warnings --import "$KIT_ROOT/tests/helpers/ts-resolve.mjs")
  else
    skip "neither bun nor a node that strips TypeScript types is installed"
  fi
  T="$BATS_TEST_TMPDIR"
  # Every shape the derivations must agree on: parameters (two in one segment too), every method
  # either spells, a method key in upper case, path-level keys that are not operations, an
  # operation neither registers (trace), an entry that is not an object, the root path.
  cat >"$T/spec.json" <<'JSON'
{ "openapi": "3.1.0", "info": { "title": "toy", "version": "1" }, "paths": {
  "/api/notes": { "summary": "notes", "parameters": [], "get": {}, "POST": {} },
  "/api/notes/{id}": { "get": {}, "put": {}, "patch": {}, "delete": {}, "head": {}, "options": {}, "trace": {} },
  "/api/notes/{id}/share/{userId}": { "post": {} },
  "/api/files/{name}.{ext}": { "get": {} },
  "/api/v1.2/odd-name_ok/{a-b}": { "get": {} },
  "/api/broken": "not an object",
  "/": { "get": {} } } }
JSON
  cat >"$T/exemptions.json" <<'JSON'
{ "POST /api/notes": { "encryption": "response-only", "reason": "a multipart upload" },
  "GET /api/files/:name.:ext": { "encryption": "request-only", "reason": "a file the browser saves" },
  "DELETE /api/notes/:id": { "encryption": "none", "reason": "no body either way" },
  "GET /api/gone": { "encryption": "none", "reason": "stale, and harmless to both" } }
JSON
  cat >"$T/ts-side.ts" <<TS
import { readFileSync } from 'node:fs';
import { deriveEndpoints } from '$HONO_TPL/scripts/lib/openapi-endpoints.ts';

const [spec, exemptions] = process.argv.slice(2).map((path) => JSON.parse(readFileSync(path, 'utf8')));
for (const e of deriveEndpoints(spec, exemptions)) {
  console.log([e.method, e.pattern, e.encryption, e.reason ?? ''].join('\t'));
}
TS
}

# mjs_side <lib>: the same lines from a payload-registry.mjs, in its own order.
mjs_side() {
  cat >"$T/mjs-side.mjs" <<MJS
import { readFileSync } from 'node:fs';
import { deriveEndpoints } from '$1';

const [spec, exemptions] = process.argv.slice(2).map((path) => JSON.parse(readFileSync(path, 'utf8')));
for (const e of deriveEndpoints(spec, exemptions)) {
  console.log([e.method, e.pattern, e.policy, e.reason].join('\t'));
}
MJS
  node "$T/mjs-side.mjs" "$T/spec.json" "$T/exemptions.json"
}

@test "the TypeScript and the Node derivation give the same methods, patterns, policies and reasons" {
  "${TS[@]}" "$T/ts-side.ts" "$T/spec.json" "$T/exemptions.json" | LC_ALL=C sort >"$T/ts.tsv"
  mjs_side "$(tpl_of go)/scripts/lib/payload-registry.mjs" >"$T/mjs.tsv"
  LC_ALL=C sort "$T/mjs.tsv" | diff "$T/ts.tsv" -
  [ "$(wc -l <"$T/ts.tsv")" -eq 12 ]
  grep -qxF "$(printf 'GET\t/api/files/:name.:ext\trequest-only\ta file the browser saves')" "$T/ts.tsv"
  grep -qxF "$(printf 'POST\t/api/notes/:id/share/:userId\tstrict\t')" "$T/ts.tsv"
  grep -qxF "$(printf 'GET\t/api/v1.2/odd-name_ok/:a-b\tstrict\t')" "$T/ts.tsv"
  # The Node side is already in the order every emitter writes: by method, then by pattern.
  LC_ALL=C sort -c -t "$(printf '\t')" -k1,1 -k2,2 "$T/mjs.tsv"
}

@test "a Node derivation that drifted from the TypeScript one is caught" {
  "${TS[@]}" "$T/ts-side.ts" "$T/spec.json" "$T/exemptions.json" | LC_ALL=C sort >"$T/ts.tsv"
  cp "$(tpl_of go)/scripts/lib/payload-registry.mjs" "$T/drifted.mjs"
  replace_once "$T/drifted.mjs" "route.replace(/\\{([^}]+)\\}/g, ':\$1')" "route.replace(/\\{([^}]+)\\}/g, '{\$1}')"
  mjs_side "$T/drifted.mjs" | LC_ALL=C sort >"$T/drifted.tsv"
  run diff "$T/ts.tsv" "$T/drifted.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/api/notes/{id}"* ]]
}
