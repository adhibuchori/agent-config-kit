#!/usr/bin/env bash
# Migration gate for goose SQL files in db/migrations (Rules 11 and 12). goose records only version
# numbers, never what a file said, so an edited migration that already ran is never detected by the
# tool itself. This fails, against the base branch, on:
#   - a migration the base already has that was changed, deleted or renamed: a database may have run
#     it; a schema change is a new file;
#   - a new migration whose version is not above the base's newest: goose refuses it out of order;
#   - a file that is not <version>_<name>.sql, or two files with one version;
#   - CREATE INDEX CONCURRENTLY (or DROP/REINDEX ... CONCURRENTLY) in a file without
#     `-- +goose NO TRANSACTION`: it cannot run inside the transaction goose wraps a file in;
#   - what `goose validate` refuses.
# With squawk on PATH (the version scripts/check/tools.env pins) it also lints the new files, Down
# sections left out; the quality gate always does.
#
#   bash scripts/check/migrations.sh [--base <ref>]
#
# The base is --base, else MIGRATIONS_BASE, else the first of origin/HEAD, origin/main, main,
# origin/master, master that exists. Without a base (a repo with no commits yet) the append-only
# part is skipped and says so.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
# Nothing downloads a toolchain, and go.mod and go.sum are never rewritten.
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly

DIR=db/migrations
BASE="${MIGRATIONS_BASE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
  --base) BASE="${2:-}" && shift ;;
  *) echo "usage: bash scripts/check/migrations.sh [--base <ref>]" >&2 && exit 2 ;;
  esac
  shift
done

if [ ! -d "$DIR" ]; then
  echo "migrations: no $DIR yet (or this repo owns no schema); nothing to check"
  exit 0
fi
failed=0
fail() {
  echo "migrations: $*"
  failed=1
}

version_of() {
  local name="${1##*/}"
  printf '%s' "${name%%_*}"
}

# ── names, versions, transactions ──────────────────────────────────────────────────────────────
count=0
seen=" "
for f in "$DIR"/*; do
  [ -e "$f" ] || continue
  count=$((count + 1))
  name="${f##*/}"
  if ! [[ "$name" =~ ^[0-9]+_[a-z0-9_]+\.sql$ ]]; then
    fail "$f: name it <version>_<snake_case_name>.sql (goose create <name> sql)"
    continue
  fi
  v="$(version_of "$name")"
  case "$seen" in *" $((10#$v)) "*) fail "$f: version $v is used twice" ;; esac
  seen="$seen$((10#$v)) "
  if grep -qiE '(create|drop)[[:space:]]+(unique[[:space:]]+)?index[[:space:]]+concurrently|reindex[[:space:]].*concurrently' "$f" &&
    ! grep -qE '^--[[:space:]]*\+goose NO TRANSACTION' "$f"; then
    fail "$f: CONCURRENTLY cannot run in a transaction; put it in a file of its own that starts with -- +goose NO TRANSACTION (Rule 12)"
  fi
done
if [ "$count" -eq 0 ]; then
  echo "migrations: $DIR is empty; nothing to check yet"
  exit 0
fi

# ── append-only against the base ───────────────────────────────────────────────────────────────
if [ -z "$BASE" ]; then
  for ref in origin/HEAD origin/main main origin/master master; do
    if git rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1; then
      BASE="$ref"
      break
    fi
  done
fi
new_files=()
if [ -z "$BASE" ] || ! git rev-parse -q --verify HEAD >/dev/null 2>&1; then
  echo "migrations: no base branch to compare with; the append-only check is skipped"
else
  mb="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "migrations: $BASE and HEAD share no history" >&2; exit 2; }
  newest=0
  while IFS= read -r path; do
    v="$(version_of "$path")"
    [[ "$v" =~ ^[0-9]+$ ]] && [ "$((10#$v))" -gt "$newest" ] && newest=$((10#$v))
  done < <(git ls-tree -r --name-only "$mb" -- "$DIR/")
  while IFS=$'\t' read -r status path rest; do
    case "$status" in
    A) new_files+=("$path") ;;
    R*) fail "$path: renamed to ${rest:-?}; a migration on $BASE never changes" ;;
    *) fail "$path: $([ "$status" = D ] && echo deleted || echo changed); a migration on $BASE never changes (Rule 11)" ;;
    esac
  done < <(git diff --name-status -M "$mb" -- "$DIR/")
  while IFS= read -r path; do
    [ -n "$path" ] && new_files+=("$path")
  done < <(git ls-files --others --exclude-standard -- "$DIR/")
  for path in ${new_files[@]+"${new_files[@]}"}; do
    v="$(version_of "$path")"
    if [[ "$v" =~ ^[0-9]+$ ]] && [ "$((10#$v))" -le "$newest" ]; then
      fail "$path: version $v is not above $newest, the newest on $BASE; goose refuses it out of order"
    fi
  done
  echo "migrations: compared with $BASE: ${#new_files[@]} new file(s)"
fi

# ── goose, then squawk ─────────────────────────────────────────────────────────────────────────
if ! go tool goose -dir "$DIR" validate; then
  fail "goose validate refused the folder (above)"
fi
if command -v squawk >/dev/null 2>&1; then
  for path in ${new_files[@]+"${new_files[@]}"}; do
    [ -f "$path" ] || continue
    sed '/^--[[:space:]]*+goose Down/,$d' "$path" | squawk --config .squawk.toml --stdin-filepath "$path" ||
      fail "$path: squawk (above)"
  done
else
  echo "migrations: squawk is not installed; the quality gate lints new migrations with it"
fi

[ "$failed" -eq 0 ] && echo "migrations: $count file(s) checked"
exit "$failed"
