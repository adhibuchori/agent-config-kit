#!/usr/bin/env bats
# actions/strip-ai: strip, back-merge and verify against a real bare origin with dev and prod, as
# the action runs them after a merge into prod. Also the refusals: wrong checkout, bad branch
# names, a path that escapes the repo, and a production branch that still tracks a stripped path.

load helpers

setup() {
  ci_isolate
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  export STRIP_AI_LIST="$BATS_TEST_TMPDIR/stripped.txt"
  git init -q --bare -b dev "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  cd "$WORK" || return 1
  git checkout -q -b dev
  mkdir -p .claude/rules src
  printf 'rule\n' >.claude/rules/a.md
  printf '{}\n' >.claude/agent-config-kit.lock
  printf '# agents\n' >AGENTS.md
  printf '# claude\n' >CLAUDE.md
  printf 'export const app = 1;\n' >src/app.ts
  printf 'debug\n' >debug-panel.config.ts
  git add -A && git commit -q -m base
  git push -q origin dev
  git checkout -q -b prod
  printf 'export const app = 2;\n' >src/app.ts
  git commit -qam "the merged change"
  git push -q origin prod
}

strip() { run --separate-stderr bash "$STRIP/strip-ai.sh"; }
back_merge() { run --separate-stderr bash "$STRIP/back-merge.sh"; }
verify() { run --separate-stderr bash "$STRIP/verify-strip.sh"; }

@test "strip-ai: prod loses the agent config, dev keeps it, and verify agrees" {
  strip
  [ "$status" -eq 0 ]
  [[ "$output" == *"paths stripped: 4"* ]]
  [ -z "$(git ls-tree -r --name-only origin/prod -- .claude AGENTS.md CLAUDE.md)" ]
  git cat-file -e origin/prod:src/app.ts
  git cat-file -e origin/prod:debug-panel.config.ts
  back_merge
  [ "$status" -eq 0 ]
  git fetch -q origin
  git cat-file -e origin/dev:.claude/rules/a.md
  git cat-file -e origin/dev:AGENTS.md
  [ "$(git show origin/dev:src/app.ts)" = "export const app = 2;" ]
  verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod tracks none of the stripped paths"* ]]
  [[ "$output" == *"dev still has every stripped path"* ]]
}

@test "strip-ai: extra-paths strips a glob pattern too, and verify sees globs" {
  STRIP_AI_EXTRA_PATHS='debug*.config.ts' strip
  [ "$status" -eq 0 ]
  run ! grep -q debug-panel <<<"$(git ls-tree -r --name-only origin/prod)"
  STRIP_AI_EXTRA_PATHS='debug*.config.ts' STRIP_AI_BACK_MERGE=false verify
  [ "$status" -eq 0 ]
}

@test "strip-ai: a second run has nothing to strip, and back-merge sees prod already merged" {
  strip && back_merge
  git checkout -q prod && git pull -q origin prod
  strip
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to strip"* ]]
  back_merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"already part of dev"* ]]
}

@test "strip-ai: verify fails while prod still tracks a stripped path, or dev lost one" {
  printf '.claude/rules/a.md\n' >"$STRIP_AI_LIST"
  verify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"still tracked on prod"* ]]
  strip
  git checkout -q dev && git rm -q -r .claude && git commit -qm "lose it" && git push -q origin dev
  git checkout -q prod
  verify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"also missing on dev"* ]]
}

@test "strip-ai: refuses a checkout of the wrong branch" {
  git checkout -q dev
  strip
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"check out 'prod'"* ]]
}

@test "strip-ai: refuses bad branch names, one branch for both, and a path outside the repo" {
  STRIP_AI_PROD_BRANCH='pr od' strip
  [ "$status" -eq 2 ]
  STRIP_AI_DEV_BRANCH=prod strip
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"both 'prod'"* ]]
  STRIP_AI_EXTRA_PATHS='../outside' strip
  [ "$status" -eq 2 ]
  STRIP_AI_EXTRA_PATHS='--force' strip
  [ "$status" -eq 2 ]
  [ -n "$(git ls-tree -r --name-only origin/prod -- .claude)" ]
}

@test "strip-ai: custom branch names" {
  git push -q origin prod:main dev:develop
  git checkout -q -b main origin/main
  STRIP_AI_PROD_BRANCH=main STRIP_AI_DEV_BRANCH=develop strip
  [ "$status" -eq 0 ]
  STRIP_AI_PROD_BRANCH=main STRIP_AI_DEV_BRANCH=develop back_merge
  [ "$status" -eq 0 ]
  STRIP_AI_PROD_BRANCH=main STRIP_AI_DEV_BRANCH=develop verify
  [ "$status" -eq 0 ]
  [ -n "$(git ls-tree -r --name-only origin/prod -- .claude)" ]
}
