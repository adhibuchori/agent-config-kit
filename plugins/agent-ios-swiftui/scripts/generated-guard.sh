#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit and Serena's writes): generated output changes only through its
# generator. The guarded paths are generatedPaths in .claude/agent-config.json (repo-relative files
# or folders); the default covers a generated API client and a copied OpenAPI contract. Optional:
# wire it where the repo has generated files (frontends, docs sites, Go and Rust services).
#
# A file can also say it is generated in its own header, wherever it lives: a Go file whose
# "// Code generated ... DO NOT EDIT." line comes before the package clause (go help generate), and
# a Rust file with @generated in a comment among its first five lines, where rustfmt looks for it.
# Only a file that exists has a header, and a folder-wide replace_in_files is judged by
# generatedPaths alone.
#
# A symlink is judged as named and as the file it points to, since a write lands there.
#
# Fails closed: a payload it cannot read, a path list it cannot load, a symlink it cannot
# follow, or a replace_in_files whose reach it cannot work out (no python3, or over 5 s) refuses
# the call.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start guard "[generated-guard]"

# generatedPaths of the repo ROOT names. A key that neither python3 nor jq can read refuses the
# call rather than guarding nothing.
guarded() {
  local list p
  list="$(hook_config generatedPaths)" || hook_fail "generatedPaths could not be read."
  GUARDED=()
  GUARDED_ROOT="$ROOT"
  while IFS= read -r p; do
    p="${p%/}"
    [[ -n "$p" ]] && GUARDED+=("$p")
  done <<<"$list"
}
guarded

# replace_in_files names a folder, or the whole project, rather than the file it rewrites.
if [[ ${#GUARDED[@]} -gt 0 ]] && hook_scope_hits "${GUARDED[@]}"; then
  block "[generated-guard] BLOCKED: this replace_in_files reaches generated output (generatedPaths in .claude/agent-config.json)." \
    "Narrow relative_path, or add paths_exclude_glob, so it is not touched."
fi

# 0 when $1 is a Go or Rust file whose header marks it generated (above). The Go marker is a whole
# line before any code; past 200 lines of header the file counts as unmarked.
marked() {
  local line n=0 block="" go_re='^// Code generated .* DO NOT EDIT\.$' rs_re='^[[:space:]]*(//|/[*]|[*])'
  [[ -f "$1" && -r "$1" ]] || return 1
  case "$1" in
  *.go)
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      [[ "$n" -le 200 ]] || return 1
      line="${line%$'\r'}"
      [[ "$n" -gt 1 ]] || line="${line#$'\xef\xbb\xbf'}"
      if [[ -n "$block" ]]; then
        [[ "$line" != *'*/'* ]] || block=""
        continue
      fi
      [[ "$line" =~ $go_re ]] && return 0
      [[ "$line" =~ ^[[:space:]]*$ || "$line" == //* ]] && continue
      if [[ "$line" == /[*]* ]]; then
        [[ "${line#/[*]}" == *'*/'* ]] || block=1
        continue
      fi
      return 1
    done <"$1"
    ;;
  *.rs)
    while [[ "$n" -lt 5 ]] && { IFS= read -r line || [[ -n "$line" ]]; }; do
      n=$((n + 1))
      [[ "$line" =~ $rs_re && "$line" == *@generated* ]] && return 0
    done <"$1"
    ;;
  esac
  return 1
}

# $1, an absolute path: refused when it is generated output of its repo. Workspace mode: a file in
# another repo follows that repo's configuration.
judge() {
  local rel p
  hook_adopt_repo "$1"
  in_project "$1" || return 0
  rel="${1#"$ROOT"/}"
  [[ "$ROOT" == "$GUARDED_ROOT" ]] || guarded
  for p in ${GUARDED[@]+"${GUARDED[@]}"}; do
    [[ "$rel" == "$p" || "$rel" == "$p"/* ]] || continue
    case "$p" in
    openapi.* | */openapi.*)
      block "[generated-guard] BLOCKED: $rel is the API contract, exported by this service or copied from the one that owns it." \
        "Change its source (the spec, the handlers, or the owning service), then export or copy it again; never edit it by hand."
      ;;
    *)
      block "[generated-guard] BLOCKED: $rel is generated output ($p in generatedPaths)." \
        "Change its source and run the project's generator instead of editing it."
      ;;
    esac
  done
  if marked "$1"; then
    case "$1" in
    *.go) p='"// Code generated ... DO NOT EDIT."' ;;
    *) p='"@generated"' ;;
    esac
    block "[generated-guard] BLOCKED: $rel is generated output: its header says $p." \
      "Change its source and run the project's generator instead of editing it."
  fi
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
