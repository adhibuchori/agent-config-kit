#!/usr/bin/env bash
# Scans every plugin's commands, agents, skills and hook scripts with the SkillSpector build and the
# gate users' repos run (plugins/agent-core/templates/common/scripts/check/skills.sh), against the
# baseline those repos get. A plugin's own components never land in a user's repo, so the users'
# gate never sees them; this is where they are scanned.
#
# Each plugin is laid out the way a repo holds the same files (commands/ and agents/ under .claude/,
# each skill under .claude/skills/, scripts/ as .claude/hooks/) in a throwaway git repo, so the
# baseline's `partial` entries for lib.sh (target .claude/hooks) apply as written and no plugin
# needs an entry of its own. hooks/hooks.json is never staged: SkillSpector reads hook manifests
# as code (BH1) and the gate in users' repos never scans them either.
#
# Every plugin's lib.sh is a byte-identical copy of agent-core's (scripts/catalog.mjs checks it), so
# it is scanned once, with agent-core. The other plugins are scanned without it, against the
# baseline minus its lib.sh entries, which would otherwise be reported as matching nothing.
#
#   bash scripts/skills-plugins.sh [--base <ref>] [--root <kit>]
#
# --base also fails when the change adds a line to the baseline: a new suppression is a human
# decision, recorded in its own pull request, never a side effect of a feature.
# A plugin whose scan fails is scanned once more before it counts: on a slow runner SkillSpector's
# static analyzers stop after 30 s per file (runtime_limit), which no baseline can accept. A pass on
# the second run is reported as a warning; a second failure fails.
# Exit 0 clean, 1 a finding or a new baseline line, 2 a usage or setup error.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
  --base) BASE="${2:-}" && shift ;;
  --root) ROOT="$(cd "${2:-}" 2>/dev/null && pwd)" || { echo "skills-plugins: --root needs a folder" >&2; exit 2; } && shift ;;
  -h | --help) sed -n '2,24p' "$0" && exit 0 ;;
  *) echo "skills-plugins: unknown argument $1" >&2 && exit 2 ;;
  esac
  shift
done

TEMPLATE="$ROOT/plugins/agent-core/templates/common"
GATE="$TEMPLATE/scripts/check/skills.sh"
BASELINE="$TEMPLATE/.skillspector-baseline.yaml"
[ -f "$GATE" ] || { echo "skills-plugins: $GATE not found; is --root a checkout of agent-config-kit?" >&2; exit 2; }

status=0
if [ -n "$BASE" ]; then
  added="$(git -C "$ROOT" diff --unified=0 "$BASE"...HEAD -- "${BASELINE#"$ROOT"/}" |
    grep -E '^\+[^+]' | grep -vE '^\+[[:space:]]*(#|$)')"
  if [ -n "$added" ]; then
    printf '::error::this change adds to the SkillSpector baseline:\n%s\n' "$added"
    status=1
  fi
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/skills-plugins.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# The baseline for plugins scanned without lib.sh, read with SkillSpector's own interpreter, which
# ships the PyYAML that skills.sh needs as well.
if [ -f "$BASELINE" ]; then
  py="$(sed -n '1s/^#!//p' "$(readlink -f "$(command -v skillspector 2>/dev/null)" 2>/dev/null)" 2>/dev/null)"
  [ -x "$py" ] || py="python3"
  "$py" - "$BASELINE" "$WORK/baseline-without-lib.yaml" <<'PY' || { echo "::error::skills-plugins: could not read $BASELINE (PyYAML comes with the pinned SkillSpector build)" >&2; exit 2; }
import sys

import yaml

data = yaml.safe_load(open(sys.argv[1])) or {}
data["partial"] = [e for e in data.get("partial") or [] if e.get("path") != "lib.sh"]
yaml.safe_dump(data, open(sys.argv[2], "w"), sort_keys=False)
PY
fi

# A throwaway repo laid out like a user's, for plugin $1 (its folder, with a trailing slash).
stage() {
  local plugin="$1" repo="$2" kind f
  mkdir -p "$repo/scripts/check"
  for kind in commands agents; do
    if [ -d "$plugin$kind" ]; then
      mkdir -p "$repo/.claude/$kind"
      cp "$plugin$kind"/*.md "$repo/.claude/$kind/"
    fi
  done
  if [ -d "${plugin}skills" ]; then
    mkdir -p "$repo/.claude/skills"
    cp -R "${plugin}skills/." "$repo/.claude/skills/"
  fi
  if [ -d "${plugin}scripts" ]; then
    for f in "${plugin}scripts"/*; do
      [ -f "$f" ] || continue
      [ "$(basename "$plugin")" != agent-core ] && [ "$(basename "$f")" = lib.sh ] && continue
      mkdir -p "$repo/.claude/hooks"
      cp -p "$f" "$repo/.claude/hooks/"
    done
  fi
  [ -d "$repo/.claude" ] || return 1
  cp "$GATE" "$repo/scripts/check/skills.sh"
  if [ "$(basename "$plugin")" = agent-core ]; then
    [ ! -f "$BASELINE" ] || cp "$BASELINE" "$repo/.skillspector-baseline.yaml"
  else
    [ ! -f "$WORK/baseline-without-lib.yaml" ] || cp "$WORK/baseline-without-lib.yaml" "$repo/.skillspector-baseline.yaml"
  fi
  git -C "$repo" init -q && git -C "$repo" add -A &&
    git -C "$repo" -c user.name=skills -c user.email=skills@example.invalid commit -qm scan
}

scanned=0
for plugin in "$ROOT"/plugins/*/; do
  name="$(basename "$plugin")"
  repo="$WORK/$name"
  stage "$plugin" "$repo" || continue
  scanned=$((scanned + 1))
  echo "::group::$name"
  if (cd "$repo" && SKILLSPECTOR_OUT="$repo/.skillspector" bash scripts/check/skills.sh --static); then
    :
  elif (cd "$repo" && SKILLSPECTOR_OUT="$repo/.skillspector" bash scripts/check/skills.sh --static); then
    echo "::warning::$name passed only on the second run; a slow runner may have hit SkillSpector's per-file time limit"
  else
    echo "::error::$name: SkillSpector found something its gate refuses (above)"
    status=1
  fi
  echo "::endgroup::"
done

[ "$scanned" -gt 0 ] || { echo "::error::skills-plugins: no plugin component found under plugins/" >&2; exit 2; }
echo "skills-plugins: $scanned plugin(s) scanned"
exit "$status"
