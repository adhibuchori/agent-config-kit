#!/usr/bin/env bats
# shellcheck disable=SC2016 # single-quoted scripts are run by bash -c with their own $1 and $2
# The locks only the user opens (docs/unlock.md): scripts/ops/unlock.sh and the .env helpers
# scripts/env/{show,set}.sh from agent-core's templates, run in a project the way setup installs
# them, and agent-core's hooks refusing every way the agent could open a lock itself.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P" feature/work
  mkdir -p "$P/scripts/ops" "$P/scripts/env"
  cp -p "$COMMON/scripts/ops/unlock.sh" "$P/scripts/ops/"
  cp -p "$COMMON/scripts/env/show.sh" "$COMMON/scripts/env/set.sh" "$COMMON/scripts/env/envfile.py" "$P/scripts/env/"
  printf '.env\n.env.local\n.claude/state/\n' >"$P/.gitignore"
  printf 'API_KEY=probe-secret-value-123456\nPORT=3000\n' >"$P/.env"
  printf 'API_KEY=\nPORT=\n' >"$P/.env.example"
  T="$P/.claude/state/unlock"
  # The lock files are the plugin's opt-in too: every hook below runs as agent-core would.
  mkdir -p "$P/.claude" && touch "$P/.claude/agent-config-kit.lock"
  PLUGIN=(CLAUDE_PLUGIN_ROOT="$CORE" CLAUDE_PROJECT_DIR="$P")
}

unlock() { (cd "$P" && env -u npm_config_user_agent "$HOOK_BASH" scripts/ops/unlock.sh "$@"); }
left() { echo $(($(cat "$T/$1") - $(date +%s))); }

@test "unlock env opens .env edits for 20 minutes in private files; db for the minutes given" {
  run -0 --separate-stderr unlock env
  [[ "$output" =~ ^🔓\ \.env\ unlocked\ until\ [0-9]{2}:[0-9]{2}\ \(20\ min\)\ —\ lock\ now:\ \./scripts/ops/unlock\.sh\ off\ env$ ]]
  [ "$(left env)" -gt 1190 ] && [ "$(left env)" -le 1200 ]
  [ "$(mode_of "$T/env")" = 600 ] && [ "$(mode_of "$T")" = 700 ] && [ "$(mode_of "$P/.claude/state")" = 700 ]
  run -0 --separate-stderr unlock db 5
  [ "$(left db)" -gt 290 ] && [ "$(left db)" -le 300 ]
}

@test "unlock status, off <target> and off" {
  unlock env >/dev/null && unlock db >/dev/null
  run -0 --separate-stderr unlock status
  [[ "$output" == *"🔓 env  .env open until"* && "$output" == *"🔓 db   db writes open until"* ]]
  run -0 --separate-stderr unlock off env
  [ ! -e "$T/env" ] && [ -e "$T/db" ]
  run -0 --separate-stderr unlock off
  [ "$output" = "🔒 everything locked (env, db)" ]
  [ -z "$(ls -A "$T")" ]
}

@test "unlock refuses minutes outside 1..240, unknown targets and extra words (exit 2), changing nothing" {
  unlock env >/dev/null
  before="$(cat "$T/env")"
  for m in 0 241 abc -1 1.5; do
    run -2 --separate-stderr unlock env "$m"
  done
  for bad in foo "off foo" "env 5 6"; do
    # shellcheck disable=SC2086 # several words on purpose
    run -2 --separate-stderr unlock $bad
  done
  run -2 --separate-stderr unlock
  [ "$(cat "$T/env")" = "$before" ]
}

@test "only the repo's own unlock.sh runs: a symlink or a copy of it is refused and writes nothing" {
  mkdir -p "$P/notes" && ln -s ../scripts/ops/unlock.sh "$P/notes/u"
  run -2 --separate-stderr bash -c 'cd "$1" && "$2" notes/u env' _ "$P" "$HOOK_BASH"
  cp -p "$P/scripts/ops/unlock.sh" "$P/notes/copy.sh"
  run -2 --separate-stderr bash -c 'cd "$1" && "$2" notes/copy.sh env' _ "$P" "$HOOK_BASH"
  [ ! -e "$T/env" ]
}

@test "show.sh lists every key with secrets masked, and flags keys the template has that the file lacks" {
  run -0 --separate-stderr bash -c 'cd "$1" && "$2" scripts/env/show.sh .env' _ "$P" "$HOOK_BASH"
  [[ "$output" == *"API_KEY"*"prob…(26 chars)"* ]]
  [[ "$output" == *"PORT"*"3000"* ]]
  [[ "$output" != *"probe-secret-value"* ]]
  [[ "$output" == *"env is locked"* ]]
  printf 'API_KEY=\nPORT=\nSENTRY_DSN=\n' >"$P/.env.example"
  run -1 --separate-stderr bash -c 'cd "$1" && "$2" scripts/env/show.sh .env' _ "$P" "$HOOK_BASH"
  [[ "$output" == *"missing SENTRY_DSN"* ]]
}

@test "set.sh refuses while env is locked, and changes one key while it is open, with a private backup" {
  run -2 --separate-stderr bash -c 'cd "$1" && printf 3001 | "$2" scripts/env/set.sh .env PORT' _ "$P" "$HOOK_BASH"
  grep -qx 'PORT=3000' "$P/.env"
  unlock env >/dev/null
  run -0 --separate-stderr bash -c 'cd "$1" && printf 3001 | "$2" scripts/env/set.sh .env PORT' _ "$P" "$HOOK_BASH"
  grep -qx 'PORT=3001' "$P/.env"
  grep -qx 'API_KEY=probe-secret-value-123456' "$P/.env"
  backup="$(find "$P/.claude/state/env-backups" -type f | head -1)"
  [ -n "$backup" ] && [ "$(mode_of "$backup")" = 600 ]
  grep -q PORT "$P/.claude/state/env-audit.log"
  run ! grep -q 3001 "$P/.claude/state/env-audit.log"
  run -2 --separate-stderr bash -c 'cd "$1" && printf x | "$2" scripts/env/set.sh .env.example PORT' _ "$P" "$HOOK_BASH"
}

@test "the agent cannot unlock: safety-check refuses the script, its package aliases and writing the unlock files" {
  printf '{"scripts": {"unlock": "bash scripts/ops/unlock.sh"}}\n' >"$P/package.json"
  echo 4102444800 >"$BATS_TEST_TMPDIR/token"
  for cmd in "bash scripts/ops/unlock.sh env" "./scripts/ops/unlock.sh db 5" "bun unlock env" "npm run unlock env" \
    "pnpm unlock env" "yarn unlock db" "echo 9999999999 > .claude/state/unlock/env" \
    "cp $BATS_TEST_TMPDIR/token .claude/state/unlock/env" "mkdir -p .claude/state/unlock" \
    "python3 -c \"open('.claude/state/unlock/env', 'w').write('9999999999')\"" "rm -f .claude/state/unlock/env"; do
    run -2 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "$cmd")" "${PLUGIN[@]}"
    [ -n "$stderr" ] || { echo "no reason for: $cmd" >&2; return 1; }
  done
  [ ! -e "$T" ]
}

@test "the agent never reads or writes a real .env through the shell; show.sh always, set.sh only while unlocked" {
  for cmd in "cat .env" "grep API .env" "source .env" "cp .env notes.txt" "printf 'A=1' >> .env" "sed -n 1p .env.local"; do
    run -2 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "$cmd")" "${PLUGIN[@]}"
  done
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "cat .env.example")" "${PLUGIN[@]}"
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "bash scripts/env/show.sh .env")" "${PLUGIN[@]}"
  run -2 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "printf 3001 | bash scripts/env/set.sh .env PORT")" "${PLUGIN[@]}"
  unlock env >/dev/null
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "printf 3001 | bash scripts/env/set.sh .env PORT")" "${PLUGIN[@]}"
}

@test "db-guard follows the file unlock.sh db writes, and locks again on unlock off" {
  q="$(sql_payload mcp__db-prod__execute_sql "DELETE FROM sessions WHERE expired")"
  run -2 --separate-stderr hook db-guard.sh "$q" "${PLUGIN[@]}"
  unlock db 2 >/dev/null
  run -0 --separate-stderr hook db-guard.sh "$q" "${PLUGIN[@]}"
  [[ "$output" == *"unlocked database writes"* ]]
  unlock off >/dev/null
  run -2 --separate-stderr hook db-guard.sh "$q" "${PLUGIN[@]}"
}

@test "an unlock file the agent could have forged opens nothing: too long, world-readable, or a symlink" {
  q="$(sql_payload mcp__db-prod__execute_sql "DELETE FROM t")"
  mkdir -p "$T" && chmod 700 "$P/.claude/state" "$T"
  (umask 077 && echo $(($(date +%s) + 245 * 60)) >"$T/db")
  run -2 --separate-stderr hook db-guard.sh "$q" "${PLUGIN[@]}"
  echo $(($(date +%s) + 600)) >"$T/db" && chmod 644 "$T/db"
  run -2 --separate-stderr hook db-guard.sh "$q" "${PLUGIN[@]}"
  rm "$T/db" && (umask 077 && echo $(($(date +%s) + 600)) >"$BATS_TEST_TMPDIR/real") && ln -s "$BATS_TEST_TMPDIR/real" "$T/db"
  run -2 --separate-stderr hook db-guard.sh "$q" "${PLUGIN[@]}"
}
