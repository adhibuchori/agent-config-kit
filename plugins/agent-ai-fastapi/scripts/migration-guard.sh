#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit and Serena's writes): migrations change only the way their tool
# allows. Two kinds of folder, both in .claude/agent-config.json:
#   migrationsDirs            generated migrations (drizzle-kit, Alembic autogenerate): never hand-edited.
#   appendOnlyMigrationsDirs  hand-written migrations (goose, sqlx, golang-migrate): a new file is yours
#                             to write and edit until it merges; a file a protected branch already has
#                             may have run against a database, so it never changes again (ADR 0007).
#                             Empty by default: a stack's setup seeds it.
# A folder the repo does not have guards nothing, so the hook turns itself off in a repo without
# migrations. Optional: wire it in backends and data pipelines.
#
# A symlink is judged as named and as the file it points to, since a write lands there.
#
# Fails closed: a payload it cannot read, a folder list it cannot load, a symlink it cannot
# follow, a git that cannot say whether a protected branch has the file, or a replace_in_files
# whose reach it cannot work out (no python3, or over 5 s) refuses the call.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start guard "[migration-guard]"

# migrationsDirs and appendOnlyMigrationsDirs of the repo ROOT names. A key that neither python3
# nor jq can read refuses the call rather than guarding nothing.
read_dirs() { # $1 key; fills LIST
  local list d
  list="$(hook_config "$1")" || hook_fail "$1 could not be read."
  LIST=()
  while IFS= read -r d; do
    d="${d%/}"
    [[ -n "$d" ]] && LIST+=("$d")
  done <<<"$list"
}
dirs() {
  read_dirs migrationsDirs
  DIRS=(${LIST[@]+"${LIST[@]}"})
  read_dirs appendOnlyMigrationsDirs
  APPEND_DIRS=(${LIST[@]+"${LIST[@]}"})
  DIRS_ROOT="$ROOT"
}
dirs

# replace_in_files names a folder, or the whole project, rather than the file it rewrites. A folder
# that does not exist holds no file, so it never matches.
ALL_DIRS=(${DIRS[@]+"${DIRS[@]}"} ${APPEND_DIRS[@]+"${APPEND_DIRS[@]}"})
if [[ ${#ALL_DIRS[@]} -gt 0 ]] && hook_scope_hits "${ALL_DIRS[@]}"; then
  block "[migration-guard] BLOCKED: this replace_in_files reaches migrations (migrationsDirs or appendOnlyMigrationsDirs)." \
    "Narrow relative_path, or add paths_exclude_glob, so they are not touched."
fi

# The first protected branch (local, or as last fetched from origin) that holds $1, a path relative
# to ROOT, the current folder (./ keeps it right when ROOT sits below the git top level); empty when
# none does. A branch with no commit yet holds nothing. Status 1 when git cannot answer, which the
# caller turns into a refusal.
merged_on() {
  local list b ref
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  list="$(hook_config protectedBranches)" || return 1
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    for ref in "refs/heads/$b" "refs/remotes/origin/$b"; do
      git rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 || continue
      if git cat-file -e "$ref:./$1" 2>/dev/null; then
        printf '%s' "$b"
        return 0
      fi
    done
  done <<<"$list"
  return 0
}

# $1, an absolute path: refused when it is a migration its tool would not accept a change to. Workspace
# mode: a file in another repo follows that repo's configuration.
judge() {
  local rel d on
  hook_adopt_repo "$1"
  in_project "$1" || return 0
  rel="${1#"$ROOT"/}"
  [[ "$ROOT" == "$DIRS_ROOT" ]] || dirs
  for d in ${DIRS[@]+"${DIRS[@]}"}; do
    [[ -d "$d" && "$rel" == "$d"/* ]] || continue
    if [[ "$rel" == *.py && -f alembic.ini ]]; then
      block "[migration-guard] BLOCKED: $rel is an Alembic revision. Change the models, run" \
        "'alembic revision --autogenerate -m \"<description>\"' (through the project's runner), then review the generated revision."
    elif compgen -G 'drizzle.config.*' >/dev/null; then
      block "[migration-guard] BLOCKED: $rel is drizzle-kit output. Change the schema and run drizzle-kit generate" \
        "(through the project's script); a data fix goes in a new custom migration."
    else
      block "[migration-guard] BLOCKED: $rel is a generated migration ($d in migrationsDirs)." \
        "Generate a new migration with the project's tool instead of editing this one."
    fi
  done
  for d in ${APPEND_DIRS[@]+"${APPEND_DIRS[@]}"}; do
    [[ -d "$d" && "$rel" == "$d"/* ]] || continue
    on="$(merged_on "$rel")" || hook_fail "git could not say whether a protected branch already has $rel."
    [[ -n "$on" ]] || continue
    block "[migration-guard] BLOCKED: $rel is already on $on, so a database may have run it." \
      "Write a new migration that changes what this one did; a merged migration never changes."
  done
}

FILE="$(hook_file)"
[[ -n "$FILE" ]] || exit 0
SESSION_ROOT="$ROOT"
judge "$FILE"
# A write to a symlink lands in the file it points to, a dangling one included: that is judged too.
TARGET="$(hook_target "$FILE")"
[[ -n "$TARGET" ]] || hook_fail "$FILE is a symbolic link that could not be followed (no realpath, readlink or python3)."
if [[ "$TARGET" != "$FILE" ]]; then
  ROOT="$SESSION_ROOT"
  cd "$ROOT" || hook_fail "the project folder $ROOT cannot be entered."
  judge "$TARGET"
fi

exit 0
