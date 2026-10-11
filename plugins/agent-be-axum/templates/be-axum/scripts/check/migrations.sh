#!/usr/bin/env bash
# The sqlx migrations in migrations/ (Rules 11 and 12). sqlx runs every file in one transaction
# and checksums it, so:
#   - each file is <14-digit version>_<name>.sql (or .up.sql / .down.sql): sqlx::migrate! refuses
#     a stray file at compile time, a macOS ._ copy included;
#   - `-- no-transaction` counts only as the file's first bytes: after a space or a blank line it
#     is a comment, and the file runs in a transaction after all;
#   - CREATE INDEX CONCURRENTLY (and DROP INDEX or REINDEX ... CONCURRENTLY) stands alone in a
#     file that starts with that marker: Postgres refuses it inside a transaction;
#   - with --base <ref> (CI passes the pull request's base): no migration the base already has is
#     modified, deleted or renamed, and each new one has a version above the base's highest,
#     because sqlx applies a lower version silently, out of order.
#
#   bash scripts/check/migrations.sh [--base <ref>]
#
# A repo without migrations/ (its schema lives in another repo) passes. Exit 1 with one line per
# problem, 2 when the base cannot be read.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

DIR=migrations
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
  --base)
    BASE="${2:-}"
    [ -n "$BASE" ] || { echo "migrations: --base needs a ref" >&2; exit 2; }
    shift
    ;;
  *) echo "migrations: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -d "$DIR" ]; then
  echo "migrations: no $DIR/ here, so nothing to check"
  exit 0
fi

problems=0
problem() {
  echo "migrations: $1" >&2
  problems=$((problems + 1))
}

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$DIR" -mindepth 1 -maxdepth 1 | LC_ALL=C sort)

for f in ${files[@]+"${files[@]}"}; do
  name="${f#"$DIR"/}"
  if [ -d "$f" ]; then
    problem "$f: a folder; sqlx reads the files directly in $DIR/"
    continue
  fi
  [ "$name" = .gitkeep ] && continue
  if [[ ! "$name" =~ ^[0-9]{14}_[a-z0-9_]+(\.up|\.down)?\.sql$ ]]; then
    problem "$f: not <14-digit version>_<name>.sql (sqlx migrate add <name> names it)"
    continue
  fi
  marker=0
  [ "$(head -c 17 "$f")" = "-- no-transaction" ] && marker=1
  if [ "$marker" -eq 0 ] && grep -qiE '^[[:space:]]*--[[:space:]]*no-transaction' "$f"; then
    problem "$f: -- no-transaction counts only as the file's first bytes; here it is a comment"
  fi
  # The statements, with comments dropped and lines joined.
  sql="$(sed 's/--.*$//' "$f" | tr '\n' ' ')"
  if grep -qiE '(create[[:space:]]+(unique[[:space:]]+)?index|drop[[:space:]]+index|reindex[[:space:]]+[a-z]+)[[:space:]]+concurrently' <<<"$sql"; then
    if [ "$marker" -eq 0 ]; then
      problem "$f: CONCURRENTLY cannot run in a transaction; start the file with -- no-transaction"
    elif [ "$(tr -cd ';' <<<"$sql" | wc -c | tr -d ' ')" -gt 1 ]; then
      problem "$f: a -- no-transaction file holds its one CONCURRENTLY statement and nothing else"
    fi
  fi
done

if [ -n "$BASE" ]; then
  base="$(git merge-base "$BASE" HEAD 2>/dev/null)" || {
    echo "migrations: cannot find where HEAD left $BASE (fetch it, with enough history)" >&2
    exit 2
  }
  while IFS=$'\t' read -r status path _; do
    case "$status" in
    M*) problem "$path: on $BASE already, so a database may have run it; write a new migration" ;;
    D*) problem "$path: deleted, but $BASE has it; sqlx stops at a migration it ran and cannot find" ;;
    R*) problem "$path: renamed, but $BASE has it under that name; write a new migration instead" ;;
    esac
  done < <(git diff --name-status --diff-filter=MDR "$base" -- "$DIR")
  highest="$(git ls-tree --name-only "$base" -- "$DIR/" | sed -nE "s|^$DIR/([0-9]{14})_.*|\1|p" | LC_ALL=C sort | tail -1)"
  for f in ${files[@]+"${files[@]}"}; do
    version="$(sed -nE "s|^$DIR/([0-9]{14})_.*|\1|p" <<<"$f")"
    [ -n "$version" ] && [ -n "$highest" ] || continue
    git cat-file -e "$base:$f" 2>/dev/null && continue
    if [[ ! "$version" > "$highest" ]]; then
      problem "$f: version $version is not above $highest, the highest on $BASE; sqlx would apply it out of order"
    fi
  done
fi

if [ "$problems" -gt 0 ]; then
  echo "migrations: $problems problem(s); see .claude/rules/backend/postgres.md" >&2
  exit 1
fi
echo "migrations: ${#files[@]} file(s) in $DIR/ named and marked as sqlx reads them${BASE:+; none on $BASE changed}"
