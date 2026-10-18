#!/usr/bin/env bats
# Two of agent-core's check scripts, run from a project the way gates.sh runs them: folder-shape.mjs
# on Rust, Swift and Go layouts, and ai-config.sh's rule that every On-demand references pointer in
# CLAUDE.md points somewhere. Each probe that must fail has one beside it that must pass.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
}

# folder-shape.mjs reads the folder it runs in.
shape() {
  command -v node >/dev/null || skip "node is not installed"
  run --separate-stderr bash -c 'cd "$1" && node "$2"' _ "$P" "$COMMON/scripts/check/folder-shape.mjs"
}

# $@ files to create (relative to the project), each with one line.
files() {
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "$P/$f")"
    echo x >"$P/$f"
  done
}

# --- folder-shape.mjs: Rust ----------------------------------------------------------------------

@test "folder-shape, rust: src/main.rs and src/lib.rs beside the module folders pass; mod.rs and target/ do not count" {
  # src/platform/ holds a folder and only its mod.rs; src/target/ would hold both if it counted.
  files Cargo.toml src/main.rs src/lib.rs src/platform/mod.rs src/platform/db/mod.rs \
    src/platform/db/pool.rs src/routes/mod.rs src/routes/paths.rs tests/api/main.rs tests/db/main.rs \
    src/target/x.rs src/target/debug/x.rs
  shape
  [ "$status" -eq 0 ]
  [[ "$output" == *"Every folder holds files or folders"* ]]
}

@test "folder-shape, rust: a loose module beside the folders is SHAPE-1" {
  files Cargo.toml src/main.rs src/lib.rs src/util.rs src/routes/mod.rs src/things/service.rs
  shape
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"src/"*"loose file(s): util.rs"*"(SHAPE-1)"* ]]
  [[ "$stderr" != *"main.rs"* && "$stderr" != *"lib.rs"* ]]
}

@test "folder-shape: without Cargo.toml, mod.rs counts and a target/ folder is walked" {
  files src/index.ts src/lib/mod.rs src/lib/x/a.ts src/target/a.ts src/target/b/c.ts
  shape
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"src/lib/"*"mod.rs"*"(SHAPE-1)"* ]]
  [[ "$stderr" == *"src/target/"*"a.ts"*"(SHAPE-1)"* ]]
}

# --- folder-shape.mjs: Swift ---------------------------------------------------------------------

@test "folder-shape, swift: a test at the mirror of its source passes; GeneratedSources and .build are skipped" {
  files Packages/AppCore/Package.swift \
    Packages/AppCore/Sources/Domain/Money/Amount.swift \
    Packages/AppCore/Tests/DomainTests/Money/AmountTests.swift \
    Packages/AppCore/Sources/APIClient/AppProblem.swift \
    Packages/AppCore/Sources/APIClient/GeneratedSources/Types.swift \
    Packages/AppCore/Tests/APIClientTests/AppProblemTests.swift \
    Packages/AppCore/.build/debug/x.swift Packages/AppCore/.build/x.swift
  shape
  [ "$status" -eq 0 ]
  [[ "$output" == *"Packages/AppCore/Sources, Packages/AppCore/Tests"* ]]
}

@test "folder-shape, swift: a test away from its source's mirror is SHAPE-2, naming where it belongs" {
  files Packages/AppCore/Package.swift \
    Packages/AppCore/Sources/Domain/Money/Amount.swift \
    Packages/AppCore/Tests/DomainTests/AmountTests.swift
  shape
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Packages/AppCore/Tests/DomainTests/AmountTests.swift"* ]]
  [[ "$stderr" == *"move it to Packages/AppCore/Tests/DomainTests/Money/"*"(SHAPE-2)"* ]]
}

@test "folder-shape, swift: a package at the repo root is walked as Sources/ and Tests/" {
  files Package.swift Sources/Feature/List/ListModel.swift Tests/FeatureTests/ListModelTests.swift
  shape
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"move it to Tests/FeatureTests/List/"*"(SHAPE-2)"* ]]
  rm "$P/Tests/FeatureTests/ListModelTests.swift"
  files Tests/FeatureTests/List/ListModelTests.swift
  shape
  [ "$status" -eq 0 ]
}

@test "folder-shape, swift: SHAPE-1 holds inside a target" {
  files Packages/AppCore/Package.swift Packages/AppCore/Sources/Features/Loose.swift \
    Packages/AppCore/Sources/Features/List/ListModel.swift
  shape
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Packages/AppCore/Sources/Features/"*"Loose.swift"*"(SHAPE-1)"* ]]
}

# --- folder-shape.mjs: Go ------------------------------------------------------------------------

@test "folder-shape, go: cmd/ and internal/ are not walked" {
  files go.mod cmd/api/main.go internal/thing/service.go internal/thing/store/pg.go internal/loose.go
  shape
  [ "$status" -eq 0 ]
  [[ "$output" != *internal* ]]
}

# --- ai-config.sh: On-demand references pointers -------------------------------------------------

# $1 the table rows, under an "On-demand References" heading in CLAUDE.md.
pointers_md() {
  mkdir -p "$P/.claude" "$P/scripts/check"
  cp "$COMMON/scripts/check/ai-config.sh" "$P/scripts/check/"
  printf '# Project\n\n## On-demand References\n\n| Read when | File |\n| --- | --- |\n%s\n\n## Other\n\n| x | `notes/missing.md` |\n' "$1" >"$P/CLAUDE.md"
}
ai_config() {
  run --separate-stderr bash -c 'cd "$1" && bash scripts/check/ai-config.sh' _ "$P"
}

@test "ai-config: a pointer to a file that does not exist, nor its .example sibling, fails" {
  pointers_md '| The database | `.claude/DATABASE.md` |'
  ai_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error file=CLAUDE.md::On-demand references points at .claude/DATABASE.md, which does not exist (nor .claude/DATABASE.example.md)"* ]]
  # The table under another heading is not a pointer table.
  [[ "$output" != *notes/missing.md* ]]
}

@test "ai-config: the file, its .example sibling, a folder or a matching glob each satisfy a pointer" {
  pointers_md "$(printf '%s\n' \
    '| Ops | `.claude/OPERATIONS.md` |' \
    '| Database | `.claude/DATABASE.md` |' \
    '| Traps | `.claude/anti-patterns/` |' \
    '| Rare servers | `.claude/mcp/*.json` |' \
    '| Rules | `AGENTS.md` |' \
    '| Not a path | `bun run check` |' \
    '| Optional | `.claude/ANALYTICS.md` (with `analytics=yes`) |')"
  files .claude/OPERATIONS.md .claude/DATABASE.example.md .claude/anti-patterns/INDEX.md \
    .claude/mcp/vps.example.json AGENTS.md
  ai_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"AI config within budget"* ]]
}

@test "ai-config: .claude/CLAUDE.md's pointers are checked too, and a dead one names its file" {
  pointers_md '| Ops | `docs/unlock.md` |'
  files docs/unlock.md
  printf '## On-demand references\n\n| When | File |\n| --- | --- |\n| Runbook | `docs/runbook.md` |\n' >"$P/.claude/CLAUDE.md"
  ai_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error file=.claude/CLAUDE.md::On-demand references points at docs/runbook.md"* ]]
  [[ "$output" != *"file=CLAUDE.md::"* ]]
}

# --- pipefail: a pipe into grep -q ---------------------------------------------------------------

@test "no template script under pipefail pipes printf or echo into grep -q" {
  # grep -q exits at its first match; the writer then dies of SIGPIPE, and pipefail turns a found
  # line into a failed test. ai-config.sh reported a defined rule as missing this way on macOS CI.
  local hits
  hits=$(grep -rlE --include='*.sh' 'pipefail' "$KIT_ROOT/plugins" |
    xargs grep -nE "(printf|echo) [^|]*\| *grep -[a-zA-Z]*q" || true)
  [ -z "$hits" ] || {
    echo "$hits" >&2
    false
  }
}
