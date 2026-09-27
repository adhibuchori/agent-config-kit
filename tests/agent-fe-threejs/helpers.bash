# shellcheck shell=bash
# Helpers for the agent-fe-threejs tests. Every test builds its own temp repo under $BATS_TEST_TMPDIR,
# needs no network, and never writes inside this repository. Assets come from make_assets.py: valid
# headers and filler, no binary fixtures in git.

bats_require_minimum_version 1.5.0

# The .bats files that load this file read these paths.
# shellcheck disable=SC2034
{
  KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  PLUGIN="$KIT_ROOT/plugins/agent-fe-threejs"
  TEMPLATES="$PLUGIN/templates"
  TPL="$TEMPLATES/fe-threejs"
  CORE="$KIT_ROOT/plugins/agent-core"
  MAKE="$BATS_TEST_DIRNAME/make_assets.py"
}
# The runtime for the budget check: node, or THREEJS_JS=bun to prove the same file under bun.
JS="${THREEJS_JS:-node}"

# A clean environment: no plugin root, an isolated git identity, temp files in the test's folder.
tj_env() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  export TMPDIR="$BATS_TEST_TMPDIR"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
    >"$GIT_CONFIG_GLOBAL"
}

# budget_repo: $R, a site with the budget check, its default config and an empty public/.
budget_repo() {
  R="$BATS_TEST_TMPDIR/site"
  mkdir -p "$R/public" "$R/scripts/check"
  cp "$TPL/scripts/check/3d-budget.mjs" "$TPL/scripts/check/3d-budget.json" "$R/scripts/check/"
  R="$(cd "$R" && pwd -P)"
}

# asset PATH SPEC: write one asset at a repo-relative path (see make_assets.py for SPEC).
asset() {
  python3 "$MAKE" "$R/$1" "$2"
}

# config PATCH: merge a JSON object into the config (objects merge key by key; null removes a key).
config() {
  python3 - "$R/scripts/check/3d-budget.json" "$1" <<'PY'
import json, sys
path, patch = sys.argv[1], json.loads(sys.argv[2])
cfg = json.load(open(path))
def merge(base, extra):
    for key, value in extra.items():
        if value is None:
            base.pop(key, None)
        elif isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
merge(cfg, patch)
json.dump(cfg, open(path, "w"), indent=2)
PY
}

# budget [ARGS]: the check as gates.sh runs it, from the repo root.
budget() {
  (cd "$R" && "$JS" scripts/check/3d-budget.mjs "$@")
}

# shellcheck disable=SC2154 # output is set by bats' run
# Assertions are plain commands on purpose: under bash 3.2, a failing [[ ]] that is not the last
# command of a test does not trip errexit, so it would never fail the test.
assert_has() {
  case "$output" in
    *"$1"*) return 0 ;;
  esac
  printf 'expected the output to contain:\n  %s\n--- output ---\n%s\n' "$1" "$output" >&2
  return 1
}
assert_lacks() {
  case "$output" in
    *"$1"*)
      printf 'expected the output not to contain:\n  %s\n--- output ---\n%s\n' "$1" "$output" >&2
      return 1
      ;;
  esac
  return 0
}
