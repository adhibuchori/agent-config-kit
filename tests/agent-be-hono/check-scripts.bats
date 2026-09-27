#!/usr/bin/env bats
# The backend gate scripts setup installs, each proven both ways on a toy repo: what it must fail,
# what it must pass, and the "nothing was checked" case it must not report as clean.

load helpers

setup() {
  be_setup_env
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/check"
  git -C "$REPO" init -q
  REPO="$(cd "$REPO" && pwd -P)"
}

# install <template path>...: copies template files into the toy repo at the same path, mode kept.
install() {
  local rel
  for rel in "$@"; do
    mkdir -p "$REPO/$(dirname "$rel")"
    cp -p "$TPL/$rel" "$REPO/$rel"
  done
}

# package_json_from_setup: package.json holding exactly the scripts /agent-be-hono:setup adds.
package_json_from_setup() {
  python3 - "$TPL/_kit/setup.json" "$REPO/package.json" <<'PY'
import json, sys
scripts = json.load(open(sys.argv[1]))["packageScripts"]
json.dump({"name": "toy", "private": True, "scripts": scripts}, open(sys.argv[2], "w"), indent=2)
PY
}

# ── index-coverage.sh ───────────────────────────────────────────────────────────────────────────

@test "index-coverage: a foreign key with its index passes" {
  install scripts/check/index-coverage.sh
  mkdir -p "$REPO/src/db/schema"
  cp "$FIXTURES/schema/owners.ts" "$FIXTURES/schema/indexed.ts" "$REPO/src/db/schema/"
  run --separate-stderr bash "$REPO/scripts/check/index-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Every foreign key column has an index"* ]]
}

@test "index-coverage: a foreign key with no index fails and names the column, from any folder" {
  install scripts/check/index-coverage.sh
  mkdir -p "$REPO/src/db/schema"
  cp "$FIXTURES/schema/owners.ts" "$FIXTURES/schema/indexed.ts" "$FIXTURES/schema/unindexed.ts" \
    "$REPO/src/db/schema/"
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$REPO/scripts/check/index-coverage.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"column 'authorId' has .references() but no index"* ]]
  [[ "$output" != *"'ownerId'"* ]]
}

@test "index-coverage: a column-level unique() counts as an index" {
  install scripts/check/index-coverage.sh
  mkdir -p "$REPO/src/db/schema"
  cp "$FIXTURES/schema/owners.ts" "$FIXTURES/schema/unique.ts" "$REPO/src/db/schema/"
  run --separate-stderr bash "$REPO/scripts/check/index-coverage.sh"
  [ "$status" -eq 0 ]
}

@test "index-coverage: no schema says so instead of claiming coverage" {
  install scripts/check/index-coverage.sh
  run --separate-stderr bash "$REPO/scripts/check/index-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Drizzle schema files found - nothing to check"* ]]
}

# ── migrations.sh (bun replaced by a stub: no network, no drizzle-kit) ────────────────────────

migrations_repo() {
  install scripts/check/migrations.sh
  mkdir -p "$REPO/src/db/migrations" "$BATS_TEST_TMPDIR/stub"
  printf 'CREATE TABLE "owners" ("id" text PRIMARY KEY);\n' >"$REPO/src/db/migrations/0000_init.sql"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m init
  cat >"$BATS_TEST_TMPDIR/stub/bun" <<'SH'
#!/bin/sh
# Stands in for `bun run db:generate`: writes a migration when STUB_NEW is set, fails on STUB_FAIL.
[ "$1 $2" = "run db:generate" ] || exit 64
[ -z "${STUB_FAIL:-}" ] || exit 1
[ -z "${STUB_NEW:-}" ] || printf 'ALTER TABLE "owners" ADD COLUMN "name" text;\n' >src/db/migrations/0001_name.sql
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/stub/bun"
}

@test "migrations: a schema whose migrations are committed passes" {
  migrations_repo
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stub:$PATH" bash "$REPO/scripts/check/migrations.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Migrations are up to date"* ]]
}

@test "migrations: a generated migration that was never committed fails and is shown" {
  migrations_repo
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stub:$PATH" STUB_NEW=1 bash "$REPO/scripts/check/migrations.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Migrations are out of date"* ]]
  [[ "$output" == *"0001_name.sql"* ]]
  [[ "$output" == *'ADD COLUMN "name"'* ]]
}

@test "migrations: a generator that fails fails the gate" {
  migrations_repo
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stub:$PATH" STUB_FAIL=1 bash "$REPO/scripts/check/migrations.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to generate migrations"* ]]
}

# ── coverage-files.mjs ──────────────────────────────────────────────────────────────────────────

coverage_repo() {
  install scripts/check/coverage-files.mjs bunfig.toml
  mkdir -p "$REPO/src/modules/thing/__tests__" "$REPO/coverage"
  printf 'export const a = 1;\n' >"$REPO/src/modules/thing/thing.service.ts"
  printf 'export const b = 2;\n' >"$REPO/src/modules/thing/thing.handler.ts"
  printf 'import "../thing.service.ts";\n' >"$REPO/src/modules/thing/__tests__/thing.service.test.ts"
  printf 'console.log(1);\n' >"$REPO/src/index.ts"
  git -C "$REPO" add -A
}

@test "coverage-files: a source file no test loads fails and is named; exempt files are not" {
  command -v node >/dev/null || skip "node is not installed"
  coverage_repo
  printf 'SF:src/modules/thing/thing.service.ts\nend_of_record\n' >"$REPO/coverage/lcov.info"
  cd "$REPO"
  run --separate-stderr node scripts/check/coverage-files.mjs
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"src/modules/thing/thing.handler.ts"* ]]
  [[ "$stderr" != *"src/index.ts"* ]]
  [[ "$stderr" != *"thing.service.test.ts"* ]]
}

@test "coverage-files: every measured file loaded passes, absolute lcov paths included" {
  command -v node >/dev/null || skip "node is not installed"
  coverage_repo
  printf 'SF:%s/src/modules/thing/thing.service.ts\nend_of_record\nSF:src/modules/thing/thing.handler.ts\nend_of_record\n' \
    "$REPO" >"$REPO/coverage/lcov.info"
  cd "$REPO"
  run --separate-stderr node scripts/check/coverage-files.mjs
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 2 measured source file(s) are loaded by a test"* ]]
}

@test "coverage-files: no lcov report and no TypeScript under src/ are failures, not passes" {
  command -v node >/dev/null || skip "node is not installed"
  install scripts/check/coverage-files.mjs bunfig.toml
  cd "$REPO"
  run --separate-stderr node scripts/check/coverage-files.mjs
  [ "$status" -eq 2 ]
  mkdir -p coverage
  : >coverage/lcov.info
  run --separate-stderr node scripts/check/coverage-files.mjs
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"found no TypeScript under src/"* ]]
}

# ── coverage-policy.mjs against the files setup installs ────────────────────────────────────────

policy_repo() {
  install scripts/check/coverage-policy.mjs bunfig.toml scripts/check/gates.list .husky/pre-commit \
    .claude/rules/typescript/coverage.md
  package_json_from_setup
}

@test "coverage-policy: the installed bunfig, gates.list, pre-commit and package scripts pass together" {
  command -v node >/dev/null || skip "node is not installed"
  policy_repo
  cd "$REPO"
  run --separate-stderr node scripts/check/coverage-policy.mjs
  [ "$status" -eq 0 ]
}

@test "coverage-policy: a test:coverage that skips coverage-files.mjs fails" {
  command -v node >/dev/null || skip "node is not installed"
  policy_repo
  python3 - "$REPO/package.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["scripts"]["test:coverage"] = "bun test src --coverage"
json.dump(p, open(sys.argv[1], "w"))
PY
  cd "$REPO"
  run --separate-stderr node scripts/check/coverage-policy.mjs
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"test:coverage must run scripts/check/coverage-files.mjs"* ]]
}

@test "coverage-policy: an exemption with no reason above it fails" {
  command -v node >/dev/null || skip "node is not installed"
  policy_repo
  python3 - "$REPO/bunfig.toml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('coveragePathIgnorePatterns = [\n', 'coveragePathIgnorePatterns = [\n  "src/unexplained.ts",\n\n', 1)
open(p, "w").write(s)
PY
  cd "$REPO"
  run --separate-stderr node scripts/check/coverage-policy.mjs
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"'src/unexplained.ts' has no reason comment above it"* ]]
}

# ── module-mocks.ts and constants.ts (bun) ───────────────────────────────────────────────────────

@test "module-mocks: a per-file mock.module fails; a test that steers the shared doubles passes" {
  command -v bun >/dev/null || skip "bun is not installed"
  install scripts/check/module-mocks.ts
  mkdir -p "$REPO/src/modules/thing/__tests__"
  printf 'import { test } from "bun:test";\ntest("x", () => {});\n' \
    >"$REPO/src/modules/thing/__tests__/thing.service.test.ts"
  run --separate-stderr bun "$REPO/scripts/check/module-mocks.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 test file(s), 0 mock.module call(s)"* ]]
  printf 'import { mock } from "bun:test";\nvoid mock.module("some-sdk", () => ({}));\n' \
    >>"$REPO/src/modules/thing/__tests__/thing.service.test.ts"
  run --separate-stderr bun "$REPO/scripts/check/module-mocks.ts"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"replaces 'some-sdk'"* ]]
}

@test "module-mocks: no test file under src/ is a failure" {
  command -v bun >/dev/null || skip "bun is not installed"
  install scripts/check/module-mocks.ts
  mkdir -p "$REPO/src"
  run --separate-stderr bun "$REPO/scripts/check/module-mocks.ts"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no test files under src/"* ]]
}

@test "constants: the empty config setup installs refuses to pass on nothing" {
  command -v bun >/dev/null || skip "bun is not installed"
  install scripts/check/constants.ts scripts/check/constants.config.json
  mkdir -p "$REPO/src"
  run --separate-stderr bun "$REPO/scripts/check/constants.ts"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"lists no home, so nothing was checked"* ]]
}

@test "constants: a role retyped outside its home fails; imported from the home it passes" {
  command -v bun >/dev/null || skip "bun is not installed"
  install scripts/check/constants.ts
  mkdir -p "$REPO/src/lib/constants" "$REPO/src/modules/thing"
  printf '[{"name": "roles", "home": "src/lib/constants/roles.ts", "allow": []}]\n' \
    >"$REPO/scripts/check/constants.config.json"
  printf "export const ROLE = { admin: 'admin', member: 'member' } as const;\n" >"$REPO/src/lib/constants/roles.ts"
  printf "import { ROLE } from '../../lib/constants/roles.ts';\nexport const isAdmin = (r: string) => r === ROLE.admin;\n" \
    >"$REPO/src/modules/thing/thing.service.ts"
  run --separate-stderr bun "$REPO/scripts/check/constants.ts"
  [ "$status" -eq 0 ]
  printf "export const isMember = (r: string) => r === 'member';\n" >>"$REPO/src/modules/thing/thing.service.ts"
  run --separate-stderr bun "$REPO/scripts/check/constants.ts"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"'member' must come from src/lib/constants/roles.ts"* ]]
}
