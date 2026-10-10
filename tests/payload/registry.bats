#!/usr/bin/env bats
# The payload registry the Go, Rust and Swift stacks share (scripts/{lib,generate,check}/
# payload-registry.mjs): every check item proven both ways for each of the three emitters, on a toy
# repo built from the template that ships the language, and each emitted file byte for byte against
# the shape its port compiles (tests/fixtures/payload/registry/). The format tests run gofmt,
# rustfmt and swift-format where they are installed and say so where they are not.

load helpers

LANGS="go rust swift"

setup() {
  command -v node >/dev/null 2>&1 || skip "node is not installed"
}

# fresh <language>: a repo for the language with its registry generated; prints its path.
fresh() {
  local repo
  repo="$(registry_repo "$BATS_TEST_TMPDIR/$1" "$1")"
  (cd "$repo" && node scripts/generate/payload-registry.mjs >/dev/null)
  printf '%s' "$repo"
}

# regenerate <repo>: the generator, which must succeed.
regenerate() { (cd "$1" && node scripts/generate/payload-registry.mjs >/dev/null); }

@test "no payload.config.json: the check says the contract is not adopted and passes; the generator writes nothing" {
  local lang repo
  for lang in $LANGS; do
    repo="$(registry_repo "$BATS_TEST_TMPDIR/$lang" "$lang")"
    rm "$repo/payload.config.json"
    check "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"has not adopted the payload contract; nothing to check"* ]]
    generate "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"no payload.config.json; the payload contract is not adopted here"* ]]
    [ ! -e "$repo/$(registry_of "$lang")" ]
  done
}

@test "each emitter writes the shape its port compiles, and the check passes on it" {
  local lang repo
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    cmp "$repo/$(registry_of "$lang")" "$FIXTURES/$(basename "$(registry_of "$lang")")"
    check "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"8 endpoint(s) in $(registry_of "$lang") ($lang); peers checked: 0; all checks passed"* ]]
  done
}

@test "the switch: off fails, strict passes, and a typo or no switch is refused instead of read as either" {
  local lang repo
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    json_set "$repo/payload.config.json" 'd["encryption"] = "off"'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'switch: payload.config.json says "off"; commit "strict"'* ]]
    json_set "$repo/payload.config.json" 'd["encryption"] = "stirct"'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'payload.config.json: encryption must be "strict" or "off", not "stirct"'* ]]
    json_set "$repo/payload.config.json" 'del d["encryption"]'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'encryption must be "strict" or "off", not missing'* ]]
    json_set "$repo/payload.config.json" 'd["encryption"] = "strict"'
    check "$repo"
    [ "$status" -eq 0 ]
  done
}

@test "registry drift: a hand edit fails naming its line, a spec change fails until regenerated, a missing file fails" {
  local lang repo registry
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    registry="$(registry_of "$lang")"
    replace_once "$repo/$registry" '"/api/notes/:id"' '"/api/notes/:noteId"'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"registry drift: $registry differs from what $(spec_of "$lang") and the exemptions imply (first at line "* ]]
    [[ "$stderr" == *"run node scripts/generate/payload-registry.mjs, never edit it by hand"* ]]
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 0 ]
    json_set "$repo/$(spec_of "$lang")" 'd["paths"]["/api/tags"] = {"get": {"operationId": "listTags", "responses": {}}}'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"registry drift: $registry differs"* ]]
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"9 endpoint(s)"* ]]
    rm "$repo/$registry"
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"registry drift: $registry is missing; run node scripts/generate/payload-registry.mjs"* ]]
  done
}

@test "exemptions: a stale one fails; one with no reason, or one that says strict, is refused; a valid one is emitted" {
  local lang repo
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    json_set "$repo/payload.config.json" 'd["exemptions"]["GET /api/gone"] = {"encryption": "none", "reason": "removed"}'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"stale exemption: GET /api/gone is exempted in payload.config.json but $(spec_of "$lang") has no such operation"* ]]
    json_set "$repo/payload.config.json" 'del d["exemptions"]["GET /api/gone"]; d["exemptions"]["GET /api/events"]["reason"] = " "'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'payload.config.json: exemption "GET /api/events" needs a written reason'* ]]
    json_set "$repo/payload.config.json" 'd["exemptions"]["GET /api/events"] = {"encryption": "strict", "reason": "x"}'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'exemption "GET /api/events" needs an encryption other than strict'* ]]
    json_set "$repo/payload.config.json" 'd["exemptions"]["GET /api/events/{id}"] = {"encryption": "none", "reason": "x"}; del d["exemptions"]["GET /api/events"]'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"stale exemption: GET /api/events/{id}"* ]]
    json_set "$repo/payload.config.json" 'del d["exemptions"]["GET /api/events/{id}"]; d["exemptions"]["GET /api/events"] = {"encryption": "none", "reason": "a stream nothing seals"}'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"registry drift"* ]]
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 0 ]
    ! cmp -s "$repo/$(registry_of "$lang")" "$FIXTURES/$(basename "$(registry_of "$lang")")"
  done
}

# client <repo> <operation id>...: a generated client that sends these operations, declared the
# way swift-openapi-generator declares them in Types.swift.
client() {
  local repo="$1" id dir n=0
  shift
  dir="$repo/$(dirname "$(registry_of swift)")/GeneratedSources"
  mkdir -p "$dir"
  {
    printf 'internal enum Operations {\n'
    for id in "$@"; do
      n=$((n + 1))
      printf '    internal enum op%d {\n        internal static let id: Swift.String = "%s"\n    }\n' "$n" "$id"
    done
    printf '}\n'
  } >"$dir/Types.swift"
}

@test "swift: every operation the generated client sends must be registered; no client yet is skipped out loud" {
  local repo lang other
  repo="$(fresh swift)"
  check "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED the generated client: no Packages/AppCore/Sources/APIClient/GeneratedSources/ yet"* ]]
  client "$repo" listNotes getNote getPayloadHandshake
  check "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SKIPPED"* ]]
  client "$repo" listNotes archiveNote
  check "$repo"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'unregistered operation: Packages/AppCore/Sources/APIClient/GeneratedSources/ sends "archiveNote", which Packages/AppCore/Sources/APIClient/PayloadEndpoints.generated.swift does not hold'* ]]
  [[ "$stderr" != *'sends "listNotes"'* ]]
  printf '// A client the scan cannot read.\n' >"$repo/Packages/AppCore/Sources/APIClient/GeneratedSources/Types.swift"
  check "$repo"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"found no operation ID in Packages/AppCore/Sources/APIClient/GeneratedSources/"* ]]
  # A Go or Rust registry is keyed by route, not by a client's operation IDs.
  for lang in go rust; do
    other="$(fresh "$lang")"
    mkdir -p "$other/$(dirname "$(registry_of "$lang")")/GeneratedSources"
    printf 'static let id: Swift.String = "archiveNote"\n' >"$other/$(dirname "$(registry_of "$lang")")/GeneratedSources/Types.swift"
    check "$other"
    [ "$status" -eq 0 ]
  done
}

@test "swift: two operations with one operationId fail, since the registry is keyed by it" {
  local repo
  repo="$(fresh swift)"
  json_set "$repo/$(spec_of swift)" 'd["paths"]["/api/events"]["get"]["operationId"] = "listNotes"'
  check "$repo"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'registry: Packages/AppCore/Sources/APIClient/openapi.json: operationId "listNotes" names both GET /api/events and GET /api/notes'* ]]
  generate "$repo"
  [ "$status" -eq 1 ]
}

@test "swift: an operation without an operationId is keyed the way swift-openapi-generator names it" {
  local repo
  repo="$(fresh swift)"
  json_set "$repo/$(spec_of swift)" 'del d["paths"]["/api/events"]["get"]["operationId"]'
  regenerate "$repo"
  grep -F '"get/api/events": PayloadEndpoint(method: "GET", pattern: "/api/events", policy: .requestOnly),' \
    "$repo/$(registry_of swift)"
  client "$repo" listNotes get/api/events
  check "$repo"
  [ "$status" -eq 0 ]
}

@test "refusal codes: a spec without all five ENVELOPE_* codes fails, naming the missing ones; an inline enum with them passes" {
  local lang repo spec
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    spec="$(spec_of "$lang")"
    json_set "$repo/$spec" 'e = d["components"]["schemas"]["ErrorCode"]["enum"]; e.remove("ENVELOPE_EXPIRED"); e.remove("ENVELOPE_REJECTED")'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"refusal codes: Problem.code in $spec lacks ENVELOPE_EXPIRED, ENVELOPE_REJECTED"* ]]
    json_set "$repo/$spec" 'd["components"]["schemas"]["Problem"]["properties"]["code"] = {"type": "string", "enum": ["NOT_FOUND", "ENVELOPE_REQUIRED", "ENVELOPE_MALFORMED", "ENVELOPE_EXPIRED", "ENVELOPE_KEY_UNKNOWN", "ENVELOPE_REJECTED"]}'
    check "$repo"
    [ "$status" -eq 0 ]
    json_set "$repo/$spec" 'del d["components"]["schemas"]["Problem"]'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"refusal codes: $spec has no Problem.code enum"* ]]
  done
}

@test "handshake: a missing operation, a sealed one or a POST fails; exempted none passes; only an app must name one" {
  local lang repo spec
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    spec="$(spec_of "$lang")"
    json_set "$repo/payload.config.json" 'd["handshake"] = "getPayloadKey"'
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"handshake: $spec has no operation \"getPayloadKey\"; add GET /api/payload/handshake"* ]]
    json_set "$repo/payload.config.json" 'd["handshake"] = "getPayloadHandshake"; del d["exemptions"]["GET /api/payload/handshake"]'
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'handshake: GET /api/payload/handshake is "strict"; exempt it "none" in payload.config.json'* ]]
    json_set "$repo/$spec" 'p = d["paths"]["/api/payload/handshake"]; p["post"] = p.pop("get")'
    json_set "$repo/payload.config.json" 'd["exemptions"]["POST /api/payload/handshake"] = {"encryption": "none", "reason": "the key"}'
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'handshake: "getPayloadHandshake" is POST /api/payload/handshake; the handshake is a GET'* ]]
    cp "$FIXTURES/openapi.json" "$repo/$spec"
    json_set "$repo/payload.config.json" 'del d["exemptions"]["POST /api/payload/handshake"]; d["exemptions"]["GET /api/payload/handshake"] = {"encryption": "none", "reason": "the key"}'
    regenerate "$repo"
    check "$repo"
    [ "$status" -eq 0 ]
    json_set "$repo/payload.config.json" 'del d["handshake"]'
    regenerate "$repo"
    check "$repo"
    if [ "$lang" = swift ]; then
      [ "$status" -eq 1 ]
      [[ "$stderr" == *"handshake: an app agrees its key through the handshake; name its operationId"* ]]
      grep -qF 'static let handshake: PayloadEndpoint? = nil' "$repo/$(registry_of swift)"
    else
      [ "$status" -eq 0 ]
    fi
  done
}

# ts_peer <dir> <repo>: a TypeScript stack's payload.config.json (its own keys, its spec at the
# default openapi.json) with the repo's exemptions and spec.
ts_peer() {
  mkdir -p "$1"
  cp "$FIXTURES/openapi.json" "$1/openapi.json"
  python3 - "$2/payload.config.json" "$1/payload.config.json" <<'PY'
import json, sys
mine = json.load(open(sys.argv[1]))
json.dump({"encryption": "strict", "registry": "src/lib/endpoints", "exemptions": mine["exemptions"],
           "routeLiterals": {"prefix": "/api/", "allow": []}, "fetchAllow": ["src/lib/payload/"],
           "peers": []}, open(sys.argv[2], "w"), indent=2)
PY
}

@test "peers: the spec and the exemptions must equal a checked-out peer's, of any stack; a missing one is skipped out loud" {
  local lang repo app
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    ts_peer "$BATS_TEST_TMPDIR/web-$lang" "$repo"
    json_set "$repo/payload.config.json" "d['peers'] = [{'name': 'web', 'root': '../web-$lang'}, {'name': 'gone', 'root': '../gone'}]"
    check "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED peer gone: no payload.config.json at ../gone (not checked out here)"* ]]
    [[ "$output" == *"peers checked: 2"* ]]
    json_set "$BATS_TEST_TMPDIR/web-$lang/openapi.json" 'd["paths"]["/api/tags"] = {"get": {}}'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"spec parity: $(spec_of "$lang") differs from web's openapi.json"* ]]
    cp "$FIXTURES/openapi.json" "$BATS_TEST_TMPDIR/web-$lang/openapi.json"
    json_set "$BATS_TEST_TMPDIR/web-$lang/payload.config.json" 'del d["exemptions"]["GET /api/events"]'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"policy parity: the exemptions in payload.config.json differ from web's"* ]]
  done
  # Across the new stacks: the app beside its Go backend.
  repo="$(fresh go)"
  app="$(fresh swift)"
  json_set "$repo/payload.config.json" 'd["peers"] = [{"name": "app", "root": "../swift"}]'
  check "$repo"
  [ "$status" -eq 0 ]
  json_set "$app/$(spec_of swift)" 'd["info"]["version"] = "2.0.0"'
  check "$repo"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"spec parity: api/openapi.json differs from app's Packages/AppCore/Sources/APIClient/openapi.json"* ]]
}

@test "config: an unknown key, an unknown language, a registry of another language or a missing spec fails" {
  local lang repo
  for lang in $LANGS; do
    repo="$(fresh "$lang")"
    json_set "$repo/payload.config.json" 'd["exemption"] = {}'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'payload.config.json: unknown key "exemption"; the keys are encryption, spec, registry, language, handshake, exemptions, peers'* ]]
    generate "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'unknown key "exemption"'* ]]
    json_set "$repo/payload.config.json" 'del d["exemption"]; d["language"] = "kotlin"'
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'language must be "go", "rust" or "swift", not "kotlin"'* ]]
    json_set "$repo/payload.config.json" "d['language'] = '$lang'; d['registry'] = 'registry.txt'"
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"registry must name the generated"* ]]
    json_set "$repo/payload.config.json" "d['registry'] = '$(registry_of "$lang")'"
    rm "$repo/$(spec_of "$lang")"
    check "$repo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"spec: $(spec_of "$lang") not found: export the spec (a backend) or copy the backend's (an app)"* ]]
  done
}

# variants <language>: the fixture's registry, one with a single entry, and one with none.
variants() {
  local lang="$1" repo
  repo="$(fresh "$lang")"
  printf '%s\n' "$repo/$(registry_of "$lang")"
  repo="$(registry_repo "$BATS_TEST_TMPDIR/$lang-one" "$lang")"
  json_set "$repo/$(spec_of "$lang")" 'd["paths"] = {"/api/payload/handshake": d["paths"]["/api/payload/handshake"]}'
  json_set "$repo/payload.config.json" 'd["exemptions"] = {"GET /api/payload/handshake": d["exemptions"]["GET /api/payload/handshake"]}'
  regenerate "$repo"
  printf '%s\n' "$repo/$(registry_of "$lang")"
  repo="$(registry_repo "$BATS_TEST_TMPDIR/$lang-none" "$lang")"
  json_set "$repo/$(spec_of "$lang")" 'd["paths"] = {}'
  json_set "$repo/payload.config.json" 'd["exemptions"] = {}; del d["handshake"]'
  regenerate "$repo"
  printf '%s\n' "$repo/$(registry_of "$lang")"
}

@test "format: gofmt leaves every emitted Go registry as it is" {
  command -v gofmt >/dev/null 2>&1 || skip "gofmt is not installed (the Go toolchain)"
  local file
  for file in $(variants go); do
    [ -z "$(gofmt -l "$file")" ]
  done
}

@test "format: rustfmt with the be-axum settings leaves every emitted Rust registry as it is" {
  command -v rustfmt >/dev/null 2>&1 || skip "rustfmt is not installed (the Rust toolchain)"
  local file
  for file in $(variants rust); do
    rustfmt --check --config-path "$(tpl_of rust)/rustfmt.toml" "$file"
  done
}

@test "format: swift-format with the ios-swiftui settings leaves every emitted Swift registry as it is" {
  local sf=()
  if command -v swift-format >/dev/null 2>&1; then
    sf=(swift-format)
  elif command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
    sf=(xcrun swift-format)
  else
    skip "swift-format is not installed (Xcode or the Swift toolchain)"
  fi
  local file
  for file in $(variants swift); do
    "${sf[@]}" lint --strict --configuration "$(tpl_of swift)/.swift-format" "$file"
  done
}
