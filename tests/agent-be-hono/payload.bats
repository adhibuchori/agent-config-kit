#!/usr/bin/env bats
# The payload contract's checks, generator and middleware (payload-encryption=yes), and the Problem
# contract check:openapi holds, each proven both ways on a toy repo built from the templates: what it
# must fail, what it must pass, and the skip it must say out loud. The scripts run on Bun, or on Node
# with tests/helpers/ts-resolve.mjs where Bun is absent.

load helpers

FE_TPL="$KIT_ROOT/plugins/agent-fe-nextjs/templates/fe-nextjs"
AI_TPL="$KIT_ROOT/plugins/agent-ai-fastapi/templates/ai-fastapi"
GO_TPL="$KIT_ROOT/plugins/agent-be-go/templates/be-go"
AXUM_TPL="$KIT_ROOT/plugins/agent-be-axum/templates/be-axum"
IOS_TPL="$KIT_ROOT/plugins/agent-ios-swiftui/templates/ios-swiftui"

setup() {
  be_setup_env
  if command -v bun >/dev/null 2>&1; then
    TS=(bun)
  elif node -e 'process.exit(process.features.typescript ? 0 : 1)' 2>/dev/null; then
    TS=(node --no-warnings --import "$KIT_ROOT/tests/helpers/ts-resolve.mjs")
  else
    skip "neither bun nor a node that strips TypeScript types is installed"
  fi
  REPO="$(payload_repo "$BATS_TEST_TMPDIR/repo" "$TPL")"
}

# payload_repo <dir> <template>: a repo holding the payload module as setup installs it, with a
# small spec and its generated registry.
payload_repo() {
  local dir="$1" tpl="$2" rel
  mkdir -p "$dir"
  for rel in src/lib/payload scripts/lib scripts/generate; do
    mkdir -p "$dir/$rel" && cp -R "$tpl/$rel/." "$dir/$rel/"
  done
  mkdir -p "$dir/scripts/check"
  cp "$tpl/scripts/check/endpoints.ts" "$tpl/scripts/check/crypto-interop.ts" \
    "$tpl/scripts/check/payload-vectors.json" "$dir/scripts/check/"
  cp "$tpl/payload.config.json" "$dir/"
  local registry
  registry="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["registry"])' "$tpl/payload.config.json")"
  mkdir -p "$dir/$registry" && cp "$tpl/$registry/endpoints.ts" "$tpl/$registry/endpoints.generated.ts" "$dir/$registry/"
  printf '{ "name": "toy", "private": true, "type": "module" }\n' >"$dir/package.json"
  cat >"$dir/openapi.json" <<'JSON'
{ "openapi": "3.1.0", "info": { "title": "toy", "version": "1" }, "paths": {
  "/api/notes": { "get": { "responses": {} }, "post": { "responses": {} } },
  "/api/notes/{id}": { "get": { "responses": {} } },
  "/api/upload": { "post": { "responses": {} } } } }
JSON
  git -C "$dir" init -q
  (cd "$dir" && "${TS[@]}" scripts/generate/endpoints.ts >/dev/null)
  printf '%s' "$(cd "$dir" && pwd -P)"
}

config_set() { # config_set <repo> <python expression over d>
  python3 - "$1/payload.config.json" "$2" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
d = json.load(open(path))
exec(expr)
json.dump(d, open(path, "w"), indent=2)
PY
}

# replace_once <file> <old> <new>: the first occurrence only, and fail loudly when it is absent.
replace_once() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path).read()
if old not in text:
    sys.exit(f"{old!r} not found in {path}")
open(path, "w").write(text.replace(old, new, 1))
PY
}

endpoints() { run --separate-stderr bash -c 'cd "$1" && shift && "$@" scripts/check/endpoints.ts' _ "$REPO" "${TS[@]}"; }
interop() { run --separate-stderr bash -c 'cd "$1" && shift && "$@" scripts/check/crypto-interop.ts' _ "$REPO" "${TS[@]}"; }

# ── crypto-interop ─────────────────────────────────────────────────────────────────────────────

@test "crypto-interop: the shipped implementation opens every vector and refuses every replay" {
  interop
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 vector(s) opened, 5 replay(s) refused, round trip ok"* ]]
  [[ "$output" == *"1 key agreement(s) derived from both sides, 3 bad point(s) refused"* ]]
}

@test "crypto-interop: an AAD builder that drifted fails, naming the vector and the agreement" {
  replace_once "$REPO/src/lib/payload/envelope.ts" 'method.toUpperCase()' 'method.toLowerCase()'
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'vector request: AAD "1.post./api/notes'* ]]
  [[ "$stderr" == *'agreement browser-or-app key agreement: AAD "1.post./api/notes.ecdh'* ]]
}

@test "crypto-interop: a copy that derives the agreed key under another HKDF label fails, from both sides" {
  replace_once "$REPO/src/lib/payload/ecdh.ts" "'payload-envelope/v1/browser'" "'payload-envelope/v2/browser'"
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"agreement browser-or-app key agreement: the server side's key does not open the envelope"* ]]
  [[ "$stderr" == *"agreement browser-or-app key agreement: the client side's key does not open the envelope"* ]]
}

@test "crypto-interop: a copy that takes a compressed point fails; one that refuses a point with another code fails" {
  replace_once "$REPO/src/lib/payload/ecdh.ts" \
    "if (point.length !== POINT_BYTES || point[0] !== UNCOMPRESSED) {" "if (point.length < 33) {"
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"point reject compressed point: accepted, but it must be refused with ENVELOPE_MALFORMED"* ]]
  [[ "$stderr" != *"point reject not on the curve"* ]]
  # A repo with the browser client is the client side: the server refuses bad peer points, not it.
  printf 'export {};\n' >"$REPO/src/lib/payload/client.ts"
  interop
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 key agreement(s) derived from both sides, 0 bad point(s) refused"* ]]
  rm "$REPO/src/lib/payload/client.ts"
  cp "$TPL/src/lib/payload/ecdh.ts" "$REPO/src/lib/payload/"
  replace_once "$REPO/src/lib/payload/ecdh.ts" "new PayloadError('ENVELOPE_MALFORMED', 'The peer public key" \
    "new PayloadError('ENVELOPE_REJECTED', 'The peer public key"
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"point reject 64 bytes, no prefix: refused with ENVELOPE_REJECTED, not ENVELOPE_MALFORMED"* ]]
}

# vectors_edit <python statement over d>: the repo's copy of the vectors, edited.
vectors_edit() {
  python3 - "$REPO/scripts/check/payload-vectors.json" "$1" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
d = json.load(open(path))
exec(expr)
json.dump(d, open(path, "w"), indent=2)
PY
}

@test "crypto-interop: an agreement whose published HKDF info or AAD was edited fails" {
  vectors_edit 'd["agreements"][0]["info"] = "payload-envelope/v1/app"'
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'agreement browser-or-app key agreement: HKDF with info "payload-envelope/v1/app" derives another key'* ]]
  cp "$TPL/scripts/check/payload-vectors.json" "$REPO/scripts/check/"
  vectors_edit 'd["agreements"][0]["vector"]["aad"] = "1.POST./api/notes/:id.ecdh.1767225600000"'
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'AAD "1.POST./api/notes.ecdh.1767225600000" is not "1.POST./api/notes/:id.ecdh.1767225600000"'* ]]
}

@test "crypto-interop: vectors without the key agreement fail instead of skipping it" {
  vectors_edit 'del d["agreements"], d["pointRejects"]'
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'the vectors carry no `agreements` or no `pointRejects`'* ]]
}

@test "crypto-interop: an implementation that stops binding the AAD cannot open the vectors, and fails" {
  replace_once "$REPO/src/lib/payload/aes-gcm.ts" "{ name: 'AES-GCM', iv, additionalData: aad, tagLength: TAG_BITS }," "{ name: 'AES-GCM', iv, tagLength: TAG_BITS },"
  replace_once "$REPO/src/lib/payload/aes-gcm.ts" "{ name: 'AES-GCM', iv, additionalData: aad, tagLength: TAG_BITS }," "{ name: 'AES-GCM', iv, tagLength: TAG_BITS },"
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"vector request: did not open"* ]]
}

@test "crypto-interop: a peer beside the repo is sealed to and opened from, a drifted one fails, a missing one is skipped" {
  PEER="$(payload_repo "$BATS_TEST_TMPDIR/web" "$FE_TPL")"
  config_set "$REPO" 'd["peers"] = [{"name": "web", "root": "../web"}, {"name": "gone", "root": "../gone"}]'
  interop
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED peer gone"* ]]
  replace_once "$PEER/src/lib/payload/envelope.ts" 'MAX_CLOCK_SKEW_MS = 120_000' 'MAX_CLOCK_SKEW_MS = 60_000'
  interop
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"peer web: MAX_CLOCK_SKEW_MS is 60000, here 120000"* ]]
}

# ── endpoints ──────────────────────────────────────────────────────────────────────────────────

@test "endpoints: a registry generated from the spec passes" {
  endpoints
  [ "$status" -eq 0 ]
  [[ "$output" == *"all checks passed"* ]]
}

@test "endpoints: a spec change the registry has not caught up with fails, and regenerating fixes it" {
  python3 - "$REPO/openapi.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["paths"]["/api/tags"] = {"get": {"responses": {}}}
json.dump(d, open(sys.argv[1], "w"))
PY
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"registry drift: GET_TAGS (GET /api/tags) is missing"* ]]
  (cd "$REPO" && "${TS[@]}" scripts/generate/endpoints.ts >/dev/null)
  endpoints
  [ "$status" -eq 0 ]
}

@test "endpoints: a policy typed into the generated file fails; an exemption in the config with a reason passes" {
  replace_once "$REPO/src/lib/endpoints/endpoints.generated.ts" "encryption: 'strict'" "encryption: 'none'"
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"differs from what openapi.json and the exemptions imply"* ]]
  config_set "$REPO" 'd["exemptions"] = {"POST /api/upload": {"encryption": "response-only", "reason": "multipart upload"}}'
  (cd "$REPO" && "${TS[@]}" scripts/generate/endpoints.ts >/dev/null)
  endpoints
  [ "$status" -eq 0 ]
}

@test "endpoints: an exemption with no reason, or for a route the spec lacks, fails" {
  config_set "$REPO" 'd["exemptions"] = {"POST /api/upload": {"encryption": "none", "reason": " "}}'
  endpoints
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'exemption "POST /api/upload" needs a written reason'* ]]
  config_set "$REPO" 'd["exemptions"] = {"GET /api/gone": {"encryption": "none", "reason": "old"}}'
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stale exemption: GET /api/gone"* ]]
}

@test "endpoints: a committed switch that is not strict fails" {
  config_set "$REPO" 'd["encryption"] = "off"'
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'switch: payload.config.json says "off"'* ]]
}

@test "endpoints: a misspelled switch fails instead of reading as strict; an absent one is strict" {
  config_set "$REPO" 'd["encryption"] = "stirct"'
  endpoints
  [ "$status" -ne 0 ]
  [[ "$stderr" == *'payload.config.json: encryption must be "strict" or "off", not "stirct"'* ]]
  config_set "$REPO" 'del d["encryption"]'
  endpoints
  [ "$status" -eq 0 ]
}

@test "endpoints: a route literal in code fails; the same path in a comment or an API description does not" {
  mkdir -p "$REPO/src/modules/notes"
  cat >"$REPO/src/modules/notes/notes.client.ts" <<'TS'
/* Calls '/api/notes' through the registry, never by name. */
export const docs = { description: 'Lists /api/notes for the caller' };
TS
  endpoints
  [ "$status" -eq 0 ]
  printf "export const url = '/api/notes';\n" >>"$REPO/src/modules/notes/notes.client.ts"
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"route literal: src/modules/notes/notes.client.ts:3 names '/api/notes'"* ]]
}

@test "endpoints: a raw fetch outside the transport fails where fetchAllow is set" {
  mkdir -p "$REPO/src/hooks"
  printf 'export const load = () => fetch(pathOf());\n' >"$REPO/src/hooks/useNotes.ts"
  endpoints
  [ "$status" -eq 0 ]
  config_set "$REPO" 'd["fetchAllow"] = ["src/lib/payload/"]'
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"raw transport: src/hooks/useNotes.ts:1"* ]]
}

@test "endpoints: a peer spec copy that differs fails; a peer not checked out is skipped out loud" {
  PEER="$(payload_repo "$BATS_TEST_TMPDIR/web" "$FE_TPL")"
  config_set "$REPO" 'd["peers"] = [{"name": "web", "root": "../web"}, {"name": "gone", "root": "../gone"}]'
  endpoints
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED peer gone"* ]]
  printf '{ "openapi": "3.1.0", "paths": {} }\n' >"$PEER/openapi.json"
  endpoints
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"spec parity: openapi.json differs from web's"* ]]
}

@test "endpoints and crypto-interop: a repo that has not adopted the contract says so and passes" {
  rm "$REPO/payload.config.json"
  endpoints
  [ "$status" -eq 0 ]
  [[ "$output" == *"has not adopted the payload contract; nothing to check"* ]]
  interop
  [ "$status" -eq 0 ]
}

# ── the middleware's wire answers ──────────────────────────────────────────────────────────────

# middleware_repo: the seeded middleware beside the module, and the one Hono export it calls at
# runtime. Kit CI has no Hono; its createMiddleware returns the handler it is given, as this one does.
middleware_repo() {
  mkdir -p "$REPO/src/middlewares" "$REPO/node_modules/hono"
  cp "$TPL/src/middlewares/payload.middleware.ts" "$REPO/src/middlewares/"
  printf '{ "name": "hono", "type": "module", "exports": { "./factory": "./factory.js" } }\n' \
    >"$REPO/node_modules/hono/package.json"
  printf 'export const createMiddleware = (middleware) => middleware;\n' >"$REPO/node_modules/hono/factory.js"
}
probe() { run --separate-stderr "${TS[@]}" "$KIT_ROOT/tests/fixtures/payload/middleware-probe.ts" "$REPO"; }

@test "middleware: a refusal is minted from its code, and a sealed answer varies on its key headers" {
  middleware_repo
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"refusals are exact and minted from the code, sealed answers vary on their key headers"* ]]
}

@test "middleware: a refusal that sends a detail fails" {
  middleware_repo
  replace_once "$REPO/src/lib/payload/refusal.ts" "title: PAYLOAD_TITLES[code]," \
    "title: PAYLOAD_TITLES[code], detail: 'POST /api/notes takes a sealed body',"
  probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'refusal.ts: body'*'"detail":"POST /api/notes takes a sealed body"'* ]]
  [[ "$stderr" == *'refusal: body'*'"detail":'* ]]
}

@test "middleware: a refusal typed about:blank, or with one title for every code, fails" {
  middleware_repo
  replace_once "$REPO/src/lib/payload/refusal.ts" 'type: `${base}${code}`,' "type: 'about:blank',"
  probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'refusal: body {"type":"about:blank"'* ]]
  cp "$TPL/src/lib/payload/refusal.ts" "$REPO/src/lib/payload/"
  replace_once "$REPO/src/lib/payload/refusal.ts" "title: PAYLOAD_TITLES[code]," "title: 'Payload refused',"
  probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'"title":"Payload refused"'* ]]
}

@test "middleware: a middleware that takes any problem-type base fails" {
  middleware_repo
  replace_once "$REPO/src/middlewares/payload.middleware.ts" \
    "const base = checkProblemTypeBase(options.problemTypeBase);" "const base = options.problemTypeBase;"
  probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'startup: problemTypeBase "about:blank" was accepted'* ]]
}

@test "middleware: a sealed answer without Vary fails" {
  middleware_repo
  replace_once "$REPO/src/middlewares/payload.middleware.ts" "headers.append('vary', SEALED_VARY);" ""
  probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'sealed answer: Vary null'* ]]
}

# ── openapi (always installed for be-hono) ─────────────────────────────────────────────────────

openapi_repo() {
  mkdir -p "$REPO/scripts/lib"
  cp "$TPL/scripts/check/openapi.ts" "$REPO/scripts/check/"
  cp "$TPL/scripts/generate/openapi.ts" "$REPO/scripts/generate/"
  cp "$TPL/scripts/lib/openapi-document.ts" "$TPL/scripts/lib/source-scan.ts" "$REPO/scripts/lib/"
  printf '{ "name": "toy", "version": "1.2.3", "private": true, "type": "module" }\n' >"$REPO/package.json"
  cat >"$REPO/src/app.ts" <<'TS'
/* Stands in for an OpenAPIHono app: only the document builder the check calls, and the Problem
   schema src/lib/errors/problem.ts registers. */
const paths: Record<string, unknown> = { '/api/notes': { get: { responses: {} } } };
const problem = {
  type: 'object',
  required: ['type', 'title', 'status', 'code'],
  properties: {
    type: { type: 'string', format: 'uri', 'x-problem-type-base': 'https://example.invalid/problems/' },
    title: { type: 'string' },
    status: { type: 'integer' },
    code: { type: 'string', enum: ['NOT_FOUND', 'ENVELOPE_REQUIRED'] },
  },
};
const components = { schemas: { Problem: problem, ErrorCode: { type: 'string' } } };
export const app = {
  getOpenAPI31Document: (config: { openapi: string; info: object }) => ({ ...config, paths, components }),
};
TS
}
openapi_check() { run --separate-stderr bash -c 'cd "$1" && shift && "$@" scripts/check/openapi.ts' _ "$REPO" "${TS[@]}"; }

@test "openapi: an exported spec that matches passes; a stale or missing one fails" {
  openapi_repo
  rm -f "$REPO/openapi.json"
  openapi_check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"openapi.json is not committed"* ]]
  (cd "$REPO" && "${TS[@]}" scripts/generate/openapi.ts >/dev/null)
  openapi_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 path(s) in the document, the Problem contract holds, openapi.json is current"* ]]
  replace_once "$REPO/src/app.ts" "'/api/notes'" "'/api/tags'"
  openapi_check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"openapi.json is stale"* ]]
}

@test "openapi: a document with no route fails, and a repo with no app is skipped out loud" {
  openapi_repo
  replace_once "$REPO/src/app.ts" "{ '/api/notes': { get: { responses: {} } } }" "{}"
  openapi_check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"describes no route"* ]]
  rm "$REPO/src/app.ts"
  openapi_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"No src/app.ts"* ]]
}

# problem_case <old> <new> <expected stderr>: the fake app with one change, which check:openapi must
# refuse, naming it, before it compares anything with the committed spec.
problem_case() {
  openapi_repo
  replace_once "$REPO/src/app.ts" "$1" "$2"
  openapi_check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the Problem contract has"* ]]
  [[ "$stderr" == *"$3"* ]]
}

@test "openapi: a document with no Problem schema fails" {
  problem_case "schemas: { Problem: problem," "schemas: { Fault: problem," \
    "components.schemas.Problem is missing"
}

@test "openapi: a Problem whose code enum is a \$ref, or holds a code that is not upper snake case, fails" {
  problem_case "code: { type: 'string', enum: ['NOT_FOUND', 'ENVELOPE_REQUIRED'] }" \
    "code: { \$ref: '#/components/schemas/ErrorCode' }" "Problem.code carries no inline enum"
  problem_case "'NOT_FOUND'" "'not_found'" 'Problem.code "not_found" does not match ^[A-Z][A-Z0-9_]*$'
}

@test "openapi: a Problem type with no base, a base with no trailing slash, or no uri format fails" {
  problem_case "'x-problem-type-base': 'https://example.invalid/problems/'" "'x-base': 1" \
    "Problem.type has no x-problem-type-base"
  problem_case "'https://example.invalid/problems/'" "'https://example.invalid/problems'" \
    'x-problem-type-base "https://example.invalid/problems" does not end in /'
  problem_case "format: 'uri', " "" "Problem.type is not \`format: uri\`"
}

@test "openapi: about:blank as the Problem type's default or in its enum fails" {
  problem_case "format: 'uri'," "format: 'uri', default: 'about:blank'," \
    "Problem.properties.type.default is about:blank"
  problem_case "format: 'uri'," "format: 'uri', enum: ['about:blank']," \
    "Problem.properties.type.enum is about:blank"
}

# ── the copies agree ───────────────────────────────────────────────────────────────────────────

@test "the frontend and backend carry the same cipher, scripts and vectors; every other stack the same vectors" {
  local f tpl
  for f in base64url errors envelope aes-gcm codec key-ring ecdh mode policy; do
    cmp "$TPL/src/lib/payload/$f.ts" "$FE_TPL/src/lib/payload/$f.ts"
  done
  for f in lib/openapi-endpoints.ts lib/payload-agreement.ts lib/source-scan.ts generate/endpoints.ts \
    check/endpoints.ts check/crypto-interop.ts check/payload-vectors.json; do
    cmp "$TPL/scripts/$f" "$FE_TPL/scripts/$f"
  done
  for tpl in "$AI_TPL" "$GO_TPL" "$AXUM_TPL" "$IOS_TPL"; do
    cmp "$TPL/scripts/check/payload-vectors.json" "$tpl/scripts/check/payload-vectors.json"
  done
  cmp "$TPL/.claude/PAYLOAD-CONTRACT.md" "$FE_TPL/.claude/PAYLOAD-CONTRACT.md"
  cmp "$TPL/.claude/PAYLOAD-CONTRACT.md" "$AI_TPL/.claude/PAYLOAD-CONTRACT.md"
  cmp "$TPL/.claude/rules/common/payload-contract.md" "$FE_TPL/.claude/rules/common/payload-contract.md"
  cmp "$TPL/.claude/rules/common/payload-contract.md" "$AI_TPL/.claude/rules/common/payload-contract.md"
}

@test "the backend and the frontend read one error-code rule" {
  cmp "$TPL/.claude/rules/common/error-codes.md" "$FE_TPL/.claude/rules/common/error-codes.md"
}

@test "the Go, Rust and Swift stacks carry one payload registry generator and checker" {
  local f
  for f in lib/payload-registry.mjs generate/payload-registry.mjs check/payload-registry.mjs; do
    cmp "$GO_TPL/scripts/$f" "$AXUM_TPL/scripts/$f"
    cmp "$GO_TPL/scripts/$f" "$IOS_TPL/scripts/$f"
  done
}

@test "the committed vectors are exactly what the kit's own implementation produces" {
  run --separate-stderr "${TS[@]}" "$KIT_ROOT/tests/fixtures/payload/make-vectors.ts"
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") "$TPL/scripts/check/payload-vectors.json"
}
