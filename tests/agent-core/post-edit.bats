#!/usr/bin/env bats
# post-edit.sh's Go, Rust, Swift, String Catalog and Xcode project branches, run against stand-in
# tools on a PATH that holds nothing else: what each tool is asked, with which environment, what
# reaches Claude, and the silence when a tool is missing, fails or finds nothing. No real Go, Rust or
# Xcode toolchain is needed, and nothing touches the network.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P" feature/probe
  P="$(cd "$P" && pwd -P)"
  BIN="$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/tools.log"
  base_tools "$BIN"
  : >"$LOG"
}

# The programs the hook itself needs, linked into $1; no formatter, linter or compiler.
base_tools() {
  local t p
  mkdir -p "$1"
  for t in bash cat dirname basename sed grep awk tr sort head tail wc sleep git env mkdir rm touch \
    mktemp cmp readlink realpath jq python3 timeout gtimeout; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$1/$t"
  done
  return 0
}

# $1 tool name, $2 the stand-in's body: a bash script that logs its arguments and the toolchain
# variables, then does what the body says.
stub() {
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s|%%s|%%s\\n" "%s $*" "GOTOOLCHAIN=$GOTOOLCHAIN GOPROXY=$GOPROXY GOFLAGS=$GOFLAGS" "RUSTUP_AUTO_INSTALL=$RUSTUP_AUTO_INSTALL CARGO_NET_OFFLINE=$CARGO_NET_OFFLINE SQLX_OFFLINE=$SQLX_OFFLINE" >>"%s"\n' "$1" "$LOG"
    printf '%s\n' "$2"
  } >"$BIN/$1"
  chmod +x "$BIN/$1"
}

# $1 file (relative to the project): the hook after an Edit of it, the way Claude Code runs it.
edited() {
  run --separate-stderr hook post-edit.sh "$(tool_payload Edit "{\"file_path\": \"$P/$1\"}")" \
    CLAUDE_PROJECT_DIR="$P" PATH="$BIN"
}

# The additionalContext the hook printed, or nothing.
context() {
  [ -n "$output" ] || return 0
  python3 -c 'import json, sys; print(json.loads(sys.argv[1])["hookSpecificOutput"]["additionalContext"])' "$output"
}

silent() {
  [ "$status" -eq 0 ] && [ -z "$output" ] && [ -z "$stderr" ]
}

# --- Go ------------------------------------------------------------------------------------------

go_file() {
  mkdir -p "$P/internal/thing"
  printf 'package thing\n' >"$P/internal/thing/a.go"
}

@test "go: golangci-lint formats the file, then lints its package offline; a finding without a column still counts" {
  go_file
  stub golangci-lint 'case "$1" in
run) printf "internal/thing/a.go:3:1: exported: func X should have a comment (revive)\ninternal/thing/long.go:202: file-length-limit: file has 201 lines (revive)\n2 issues:\n* revive: 2\n" ;;
esac'
  edited internal/thing/a.go
  [ "$status" -eq 0 ]
  ctx="$(context)"
  [[ "$ctx" == "golangci-lint ./internal/thing:"* ]]
  [[ "$ctx" == *"internal/thing/a.go:3:1: exported"* ]]
  [[ "$ctx" == *"internal/thing/long.go:202: file-length-limit"* ]]
  [[ "$ctx" != *"issues:"* ]]
  grep -qF 'golangci-lint fmt -- internal/thing/a.go|GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=readonly|' "$LOG"
  grep -q '^golangci-lint run --allow-serial-runners .* -- ./internal/thing|GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=readonly|' "$LOG"
}

@test "go: a clean package says nothing, and a file at the root lints the root package" {
  printf 'package main\n' >"$P/main.go"
  stub golangci-lint 'case "$1" in run) echo "0 issues." ;; esac'
  edited main.go
  silent
  grep -q '^golangci-lint run .* -- \.|' "$LOG"
}

@test "go: a package-wide run is capped at 40 lines and says how many more" {
  go_file
  stub golangci-lint 'case "$1" in run) for i in $(seq 1 45); do echo "internal/thing/a.go:$i:1: unused (unused)"; done ;; esac'
  ln -sf "$(command -v seq)" "$BIN/seq"
  edited internal/thing/a.go
  ctx="$(context)"
  [[ "$ctx" == *"internal/thing/a.go:40:1:"* && "$ctx" != *"internal/thing/a.go:41:1:"* ]]
  [[ "$ctx" == *"... and 5 more" ]]
}

@test "go: without golangci-lint, gofmt -w and go vet, still offline" {
  go_file
  stub gofmt ''
  stub go 'echo "# example.invalid/m/internal/thing" >&2; echo "internal/thing/a.go:5:2: fmt.Printf format %d has arg x of wrong type string" >&2; exit 1'
  edited internal/thing/a.go
  ctx="$(context)"
  [[ "$ctx" == "go vet ./internal/thing:"$'\n'"internal/thing/a.go:5:2: fmt.Printf format"* ]]
  [[ "$ctx" != *"# example.invalid"* ]]
  grep -q '^gofmt -w -- internal/thing/a.go|GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=readonly|' "$LOG"
  grep -q '^go vet ./internal/thing|GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=readonly|' "$LOG"
}

@test "go: with no Go tool at all the hook says nothing" {
  go_file
  edited internal/thing/a.go
  silent
}

# --- Rust ----------------------------------------------------------------------------------------

rust_file() {
  mkdir -p "$P/src/routes"
  printf '[package]\nname = "svc"\n' >"$P/Cargo.toml"
  printf 'fn   app( ){}\n' >"$P/src/app.rs"
}

@test "rust: rustfmt formats through stdin and the result is written back; clippy keeps this file's lines" {
  rust_file
  stub rustfmt 'cat >/dev/null; printf "fn app() {}\n"'
  stub cargo 'printf "    Checking svc v0.1.0\nsrc/app.rs:1:1: error: used \`unwrap()\` on an \`Option\` value\nsrc/routes/mod.rs:4:9: warning: unused variable\nerror: could not compile \`svc\` (lib) due to 1 previous error\n" >&2; exit 101'
  edited src/app.rs
  [ "$status" -eq 0 ]
  [ "$(cat "$P/src/app.rs")" = 'fn app() {}' ]
  ctx="$(context)"
  [ "$ctx" = "cargo clippy src/app.rs:"$'\n'"src/app.rs:1:1: error: used \`unwrap()\` on an \`Option\` value" ]
  # No file argument: rustfmt would reformat the modules src/app.rs declares too.
  offline='|RUSTUP_AUTO_INSTALL=0 CARGO_NET_OFFLINE=true SQLX_OFFLINE=true'
  grep -F 'rustfmt --edition 2024 --emit stdout|' "$LOG" | grep -qF "$offline"
  grep -F 'cargo clippy --locked --all-targets --message-format=short|' "$LOG" | grep -qF "$offline"
}

@test "rust: an unchanged file is not rewritten, and a rustfmt that fails leaves it alone" {
  rust_file
  printf 'fn app() {}\n' >"$P/src/app.rs"
  touch -t 200001010000 "$P/src/app.rs"
  touch "$BATS_TEST_TMPDIR/ref"
  stub rustfmt 'cat'
  edited src/app.rs
  silent
  [ -z "$(find "$P/src/app.rs" -newer "$BATS_TEST_TMPDIR/ref")" ]
  printf 'fn app( {\n' >"$P/src/app.rs"
  stub rustfmt 'cat >/dev/null; echo "error: this file contains an unclosed delimiter" >&2; exit 1'
  edited src/app.rs
  silent
  [ "$(cat "$P/src/app.rs")" = 'fn app( {' ]
}

@test "rust: no Cargo.toml at the root, or cargo waiting on another build's lock, says nothing" {
  rust_file
  stub cargo 'echo "    Blocking waiting for file lock on build directory" >&2'
  edited src/app.rs
  silent
  rm "$P/Cargo.toml"
  : >"$LOG"
  edited src/app.rs
  silent
  run ! grep -q '^cargo ' "$LOG"
}

# --- Swift ---------------------------------------------------------------------------------------

swift_file() {
  mkdir -p "$P/App/Screens/My Feature"
  printf 'struct V {}\n' >"$P/App/Screens/My Feature/View.swift"
}

@test "swift: Xcode's swift-format formats in place, and swiftlint's lines about this file reach Claude" {
  swift_file
  stub xcrun 'case "$1" in --find) echo /x/swift-format ;; esac'
  # SwiftLint names files by their absolute path; this one has a space in it.
  stub swiftlint 'printf "%s\n" "'"$P"'/App/Screens/My Feature/View.swift:3:5: error: Force Cast Violation: Force casts should be avoided (force_cast)" "'"$P"'/App/Other.swift:1:1: warning: elsewhere"; exit 2'
  edited "App/Screens/My Feature/View.swift"
  [ "$status" -eq 0 ]
  [ "$(context)" = "swiftlint App/Screens/My Feature/View.swift:"$'\n'"App/Screens/My Feature/View.swift:3:5: error: Force Cast Violation: Force casts should be avoided (force_cast)" ]
  grep -qF 'xcrun swift-format format --in-place -- App/Screens/My Feature/View.swift|' "$LOG"
  grep -qF 'swiftlint lint --quiet --force-exclude -- App/Screens/My Feature/View.swift|' "$LOG"
}

@test "swift: a SwiftLint whose version differs from the config's pin says nothing" {
  swift_file
  stub swiftlint 'echo "Currently running SwiftLint 0.65.0 but configuration specified version 0.65.1." >&2; exit 2'
  edited "App/Screens/My Feature/View.swift"
  silent
}

@test "swift: without xcrun's swift-format, a swift-format on PATH formats" {
  swift_file
  stub xcrun 'exit 72'
  stub swift-format ''
  edited "App/Screens/My Feature/View.swift"
  silent
  grep -qF 'swift-format format --in-place -- App/Screens/My Feature/View.swift|' "$LOG"
  run ! grep -qF 'xcrun swift-format' "$LOG"
}

# --- String Catalogs and Xcode projects ----------------------------------------------------------

@test "xcstrings: a key missing a locale the catalog uses, or not translated, is named" {
  cat >"$P/Localizable.xcstrings" <<'JSON'
{
  "sourceLanguage": "en",
  "strings": {
    "Hello": {"localizations": {"id": {"stringUnit": {"state": "translated", "value": "Halo"}}}},
    "Bye": {},
    "Save": {"localizations": {"id": {"stringUnit": {"state": "needs_review", "value": "Simpan"}}}},
    "%lld items": {"localizations": {"id": {"variations": {"plural": {
      "one": {"stringUnit": {"state": "translated", "value": "%lld item"}},
      "other": {"stringUnit": {"state": "new", "value": "%lld item"}}}}}}},
    "Brand": {"shouldTranslate": false}
  },
  "version": "1.0"
}
JSON
  edited Localizable.xcstrings
  [ "$status" -eq 0 ]
  ctx="$(context)"
  [[ "$ctx" == "Localizable.xcstrings has strings that are not translated in every locale the catalog uses:"* ]]
  [[ "$ctx" == *'"Bye": no id'* ]]
  [[ "$ctx" == *'"Save": id is needs_review'* ]]
  [[ "$ctx" == *'"%lld items": id is new'* ]]
  [[ "$ctx" != *Hello* && "$ctx" != *Brand* ]]
}

@test "xcstrings: a complete catalog says nothing; one that is not JSON says so" {
  printf '{"sourceLanguage": "en", "strings": {"Hi": {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "Hi"}}, "id": {"stringUnit": {"state": "translated", "value": "Hai"}}}}}}\n' >"$P/Localizable.xcstrings"
  edited Localizable.xcstrings
  silent
  printf '{"strings": {' >"$P/Localizable.xcstrings"
  edited Localizable.xcstrings
  [ "$(context)" = "Localizable.xcstrings is not valid JSON." ]
}

@test "pbxproj: plutil's refusal reaches Claude; a valid project, or no plutil, says nothing" {
  mkdir -p "$P/App.xcodeproj"
  printf '// !$*UTF8*$!\n{ objects = { }; }\n' >"$P/App.xcodeproj/project.pbxproj"
  edited App.xcodeproj/project.pbxproj
  silent
  stub plutil 'echo "App.xcodeproj/project.pbxproj: OK"'
  edited App.xcodeproj/project.pbxproj
  silent
  grep -qF 'plutil -lint -- App.xcodeproj/project.pbxproj|' "$LOG"
  stub plutil 'echo "App.xcodeproj/project.pbxproj: (Unexpected character / at line 1)"; exit 1'
  edited App.xcodeproj/project.pbxproj
  [ "$(context)" = "App.xcodeproj/project.pbxproj is not a valid property list, so Xcode cannot open the project:"$'\n'"App.xcodeproj/project.pbxproj: (Unexpected character / at line 1)" ]
}

@test "the plugin's hook only speaks in a project that opted in" {
  go_file
  stub golangci-lint 'case "$1" in run) echo "internal/thing/a.go:1:1: x (revive)" ;; esac'
  run --separate-stderr hook post-edit.sh "$(tool_payload Edit "{\"file_path\": \"$P/internal/thing/a.go\"}")" \
    CLAUDE_PROJECT_DIR="$P" PATH="$BIN" CLAUDE_PLUGIN_ROOT="$CORE" CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data"
  silent
  [ ! -s "$LOG" ]
  mkdir -p "$P/.claude" && echo '{}' >"$P/.claude/agent-config.json"
  run --separate-stderr hook post-edit.sh "$(tool_payload Edit "{\"file_path\": \"$P/internal/thing/a.go\"}")" \
    CLAUDE_PROJECT_DIR="$P" PATH="$BIN" CLAUDE_PLUGIN_ROOT="$CORE" CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data"
  [[ "$(context)" == *"internal/thing/a.go:1:1: x (revive)"* ]]
}
