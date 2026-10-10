# Helpers for the payload registry tests: a toy repo per language, built from the template that
# ships that language, with the fixture spec and a payload.config.json as setup seeds it. Every
# test builds its own repo under $BATS_TEST_TMPDIR and needs no network.
# shellcheck shell=bash

bats_require_minimum_version 1.5.0

# The .bats files that load this file read these paths.
# shellcheck disable=SC2034
{
  KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  FIXTURES="$KIT_ROOT/tests/fixtures/payload/registry"
  HONO_TPL="$KIT_ROOT/plugins/agent-be-hono/templates/be-hono"
}

# tpl_of <language>: the template that ships the language.
tpl_of() {
  case "$1" in
  go) printf '%s' "$KIT_ROOT/plugins/agent-be-go/templates/be-go" ;;
  rust) printf '%s' "$KIT_ROOT/plugins/agent-be-axum/templates/be-axum" ;;
  swift) printf '%s' "$KIT_ROOT/plugins/agent-ios-swiftui/templates/ios-swiftui" ;;
  esac
}

# spec_of / registry_of <language>: where payload.config.json points, as interface.md fixes it.
spec_of() {
  case "$1" in
  go) printf 'api/openapi.json' ;;
  rust) printf 'openapi.json' ;;
  swift) printf 'Packages/AppCore/Sources/APIClient/openapi.json' ;;
  esac
}
registry_of() {
  case "$1" in
  go) printf 'internal/payload/registry.gen.go' ;;
  rust) printf 'src/payload/endpoints_generated.rs' ;;
  swift) printf 'Packages/AppCore/Sources/APIClient/PayloadEndpoints.generated.swift' ;;
  esac
}

# registry_repo <dir> <language>: the three scripts, the fixture spec and a strict config with the
# handshake exempted; prints the repo's real path. Nothing is generated yet.
registry_repo() {
  local dir="$1" lang="$2" tpl rel spec
  tpl="$(tpl_of "$lang")"
  spec="$(spec_of "$lang")"
  for rel in lib generate check; do
    mkdir -p "$dir/scripts/$rel"
    cp "$tpl/scripts/$rel/payload-registry.mjs" "$dir/scripts/$rel/"
  done
  mkdir -p "$dir/$(dirname "$spec")"
  cp "$FIXTURES/openapi.json" "$dir/$spec"
  cat >"$dir/payload.config.json" <<JSON
{
  "encryption": "strict",
  "spec": "$spec",
  "registry": "$(registry_of "$lang")",
  "language": "$lang",
  "handshake": "getPayloadHandshake",
  "exemptions": {
    "GET /api/payload/handshake": { "encryption": "none", "reason": "it hands out the key, so nothing can be sealed yet" },
    "PUT /api/notes/:id/attachments/:attachmentId/content": { "encryption": "response-only", "reason": "a multipart upload streams the file; the answer is sealed" },
    "GET /api/events": { "encryption": "request-only", "reason": "an event stream is flushed as it is written" }
  },
  "peers": []
}
JSON
  printf '%s' "$(cd "$dir" && pwd -P)"
}

# json_set <file> <python statement over d>
json_set() {
  python3 - "$1" "$2" <<'PY'
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

# generate / check <repo>: the two scripts, run from the repo root. "$1" expands in the inner shell.
# shellcheck disable=SC2016
generate() { run --separate-stderr bash -c 'cd "$1" && node scripts/generate/payload-registry.mjs' _ "$1"; }
# shellcheck disable=SC2016
check() { run --separate-stderr bash -c 'cd "$1" && node scripts/check/payload-registry.mjs' _ "$1"; }
