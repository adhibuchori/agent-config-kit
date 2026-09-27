#!/usr/bin/env bats
# templates/ai-fastapi: what /agent-ai-fastapi:setup installs. The _kit/setup.json contract, the
# paths a template may never hold, the settings merge input, the PR-only CI caller, the gate lists,
# the starters, and the pyproject.toml sections against coverage-policy.mjs.

load helpers

setup() {
  ai_setup_env
}

# Every template path, repo-relative as it lands in the user's repo (without _kit/).
template_paths() {
  (cd "$TPL" && find . -path ./_kit -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' | sort)
}

@test "_kit/setup.json: this stack, only the known keys, every answer valid" {
  local f="$TPL/_kit/setup.json"
  run jq -r '.stack' "$f"
  [ "$output" = "ai-fastapi" ]
  run jq -r 'keys - ["stack","conflictsWith","questions","seed","snippets","gitignore","packageScripts"] | length' "$f"
  [ "$output" = "0" ]
  run jq -r '[.questions[] | keys - ["id","ask","why","choices","recommended","detect","install","settings"]] | flatten | length' "$f"
  [ "$output" = "0" ]
  run jq -r '[.questions[] | . as $q | select(($q.choices | index($q.recommended)) == null) | .id] | join(",")' "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  run jq -r '[.questions[] | . as $q | (.install // {} | keys[]) | select(($q.choices | index(.)) == null)] | length' "$f"
  [ "$output" = "0" ]
  run jq -r '[.questions[].id] | (length == (unique | length))' "$f"
  [ "$output" = "true" ]
}

@test "_kit/setup.json: no unlock alias here, and every other primary stack is a conflict" {
  local f="$TPL/_kit/setup.json"
  run jq -r '.packageScripts | length' "$f"
  [ "$output" = "0" ]
  run jq -r '.conflictsWith | sort | join(",")' "$f"
  [ "$output" = "agent-be-hono,agent-docs-nextra,agent-fe-nextjs,agent-fe-nextjs-static" ]
}

@test "conflicts are mutual: each primary stack that is built names agent-ai-fastapi back" {
  local p other
  for p in agent-be-hono agent-docs-nextra agent-fe-nextjs agent-fe-nextjs-static; do
    for other in "$KIT_ROOT/plugins/$p/templates"/*/_kit/setup.json; do
      [ -f "$other" ] || continue
      run jq -r '.conflictsWith | index("agent-ai-fastapi") != null' "$other"
      [ "$output" = "true" ]
    done
  done
}

# glob_matches <glob>: 0 when a template path matches (* within a folder, ** across, ? one char).
glob_matches() {
  template_paths | python3 -c '
import re, sys
g = sys.argv[1]
rx, i = "", 0
while i < len(g):
    if g.startswith("**", i):
        rx += ".*"; i += 2
    elif g[i] == "*":
        rx += "[^/]*"; i += 1
    elif g[i] == "?":
        rx += "[^/]"; i += 1
    else:
        rx += re.escape(g[i]); i += 1
sys.exit(0 if any(re.fullmatch(rx, l.strip()) for l in sys.stdin) else 1)' "$1"
}

@test "every install and seed glob names at least one template file" {
  local g
  while IFS= read -r g; do
    glob_matches "$g" || {
      echo "matches nothing: $g" >&2
      return 1
    }
  done < <(jq -r '(.questions[].install // {} | .[][]), .seed[]' "$TPL/_kit/setup.json")
}

@test "the pyproject.toml snippet exists and is never itself a template path" {
  run jq -r '.snippets | to_entries[] | "\(.key)=\(.value)"' "$TPL/_kit/setup.json"
  [ "$output" = "pyproject.toml=snippets/pyproject.tools.toml" ]
  [ -f "$TPL/_kit/snippets/pyproject.tools.toml" ]
  [ ! -e "$TPL/pyproject.toml" ]
  [ -f "$TPL/pyproject.toml.starter" ]
}

@test "no path a template may never hold" {
  run template_paths
  [ "${#lines[@]}" -gt 30 ]
  local p
  for p in "${lines[@]}"; do
    case "$p" in
    package.json | */package.json | .gitignore | */.gitignore) false ;;
    .claude/hooks/* | .claude/commands/* | .claude/agents/* | .claude/skills/*) false ;;
    CLAUDE.md | AGENTS.md | */CLAUDE.md | */AGENTS.md) false ;;
    .env | .env.* | */.env | */.env.*)
      [[ "$p" == *.example ]] ;;
    esac
  done
  run find "$TPL" -type l
  [ -z "$output" ]
}

@test "no bytecode, cache or OS file anywhere in the plugin: setup would install it as is" {
  run find "$PLUGIN" \( -name __pycache__ -o -name '*.pyc' -o -name .DS_Store -o -name '*.swp' \) -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test ".claude/settings.json: permissions only, never a hooks key" {
  local f="$TPL/.claude/settings.json"
  run jq -r 'keys - ["$schema","permissions","sandbox","env","extraKnownMarketplaces","enabledPlugins"] | length' "$f"
  [ "$output" = "0" ]
  run jq -r 'has("hooks")' "$f"
  [ "$output" = "false" ]
  # Named tools only: `uv run <anything>` would run arbitrary code without a prompt.
  run jq -r '.permissions.allow | join(",")' "$f"
  [ "$output" = "Bash(uv run pytest:*),Bash(uv run ruff:*),Bash(uv run mypy:*),Bash(uv run lint-imports:*),Bash(uv run vulture:*),Bash(uv run deptry:*),Bash(uv run pre-commit:*),Bash(uv sync:*)" ]
  # docker compose can delete volumes (down -v): Claude asks first.
  run jq -r '.permissions.ask | join(",")' "$f"
  [ "$output" = "Bash(docker compose:*)" ]
}

@test "no path agent-core's templates/common already ships" {
  [ -d "$CORE_TPL" ] || skip "agent-core templates not built"
  local p
  while IFS= read -r p; do
    [ ! -e "$CORE_TPL/$p" ] || {
      echo "duplicates agent-core: $p" >&2
      return 1
    }
  done < <(template_paths | grep -vx '.claude/settings.json')
}

@test "the CI caller: pull requests only, read-only token, no secrets, pinned by full SHA" {
  local f="$TPL/.github/workflows/quality-gate.yml"
  run grep -nE '^[[:space:]]*(push|schedule|pull_request_target|workflow_run|workflow_dispatch):' "$f"
  [ "$status" -eq 1 ]
  run sed -n '/^on:/,/^[a-z]/p' "$f"
  [[ "$output" == *"pull_request:"* ]] || false
  [ "$(grep -c '^  [a-z_]*:' <<<"$output")" -eq 1 ]
  run grep -c 'contents: read' "$f"
  [ "$output" -eq 2 ]
  # Outside comments: no write permission, no secrets passed, no shell step.
  run bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -nE "write|secrets|inherit|run:"' _ "$f"
  [ "$status" -eq 1 ]
  # The branches agent-core's guards protect by default, so a repo with only main is gated too.
  run grep -E '^[[:space:]]*branches:' "$f"
  [ "$output" = "    branches: [dev, prod, main, master]" ]
  run grep -F '"protectedBranches": ["dev", "prod", "main", "master"]' "$PLUGIN/scripts/lib.sh"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]*uses:' "$f"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" =~ uses:\ adhibuchori/agent-config-kit/\.github/workflows/ai-fastapi-quality-gate\.yml@[0-9a-f]{40}\ \#\ v[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
}

@test "gates.list and the pre-commit config run only scripts this stack or agent-core installs" {
  local s
  run grep -vE '^(#|$)' "$TPL/scripts/check/gates.list"
  [ "${#lines[@]}" -ge 10 ]
  while IFS= read -r s; do
    if [ -e "$TPL/$s" ]; then continue; fi
    [ -d "$CORE_TPL" ] || skip "agent-core templates not built (needed for $s)"
    [ -e "$CORE_TPL/$s" ] || {
      echo "no plugin installs $s" >&2
      return 1
    }
  done < <(grep -ohE '(scripts|\.github)/[A-Za-z0-9_./-]+\.(sh|mjs|py)' \
    "$TPL/scripts/check/gates.list" "$TPL/.pre-commit-config.yaml" | sort -u)
  run grep -nE 'hook-probes|workflows\.sh|ai-config-probes' "$TPL/scripts/check/gates.list" "$TPL/.pre-commit-config.yaml"
  [ "$status" -eq 1 ]
}

@test "the starters and project docs point at plugin components, not copied ones" {
  run grep -rnE '\.claude/hooks/[a-z-]+\.sh|\.github/scripts/|strip-ai-on-pr|SETUP\.md' "$TPL"
  [ "$status" -eq 1 ]
  # Every example the starter's On-demand References table names is one a plugin installs.
  local ex
  while IFS= read -r ex; do
    [ -e "$TPL/.claude/$ex" ] || [ -e "$CORE_TPL/.claude/$ex" ] || {
      echo "CLAUDE.md.starter names $ex, which no plugin installs" >&2
      return 1
    }
  done < <(grep -oE '[A-Z][A-Z-]+\.example\.md' "$TPL/CLAUDE.md.starter" | sort -u)
  # agent-core's commands, always by their namespaced name.
  # shellcheck disable=SC2016 # backticks are Markdown here, not a command
  run grep -rnE '`/(ship|checkpoint|review|promote|commit|plan|rca|create-pr|merge-pr)`' "$TPL"
  [ "$status" -eq 1 ]
}

@test "the CLAUDE.md fragment is short and has no heading above ###" {
  local f="$TPL/_kit/claude-md.md"
  run grep -nE '^#{1,2} ' "$f"
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$f")" -le 12 ]
  grep -q 'agent-ai-fastapi:ai-reviewer' "$f"
  grep -q './scripts/ops/unlock.sh' "$f"
}

@test "the snippet carries the starter's dev group and [tool.*] sections, and nothing else" {
  local py
  py="$(toml_python)" || skip "no python3 with tomllib (3.11+)"
  "$py" - "$TPL/pyproject.toml.starter" "$TPL/_kit/snippets/pyproject.tools.toml" <<'PY'
import sys, tomllib
starter, snippet = (tomllib.load(open(p, "rb")) for p in sys.argv[1:])
assert sorted(snippet) == ["dependency-groups", "tool"], sorted(snippet)
assert snippet["dependency-groups"] == starter["dependency-groups"]
assert snippet["tool"] == starter["tool"]
PY
}

@test "coverage-policy.mjs passes the starter pyproject.toml with the pre-commit config" {
  command -v node >/dev/null || skip "node not installed"
  make_project service
  cp "$TPL/pyproject.toml.starter" "$PROJ/pyproject.toml"
  cp "$TPL/.pre-commit-config.yaml" "$TPL/scripts/check/gates.list" "$PROJ/" 2>/dev/null || true
  mkdir -p "$PROJ/scripts/check"
  cp "$TPL/scripts/check/gates.list" "$PROJ/scripts/check/"
  # shellcheck disable=SC2016 # $1 and $2 expand in the child shell
  run --separate-stderr bash -c 'cd "$1" && node "$2"' _ "$PROJ" "$TPL/scripts/check/coverage-policy.mjs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thresholds at 100"* ]] || false
}

@test "coverage-policy.mjs passes a project's own [project] plus the snippet, and fails a lowered floor" {
  command -v node >/dev/null || skip "node not installed"
  make_project service
  cat "$TPL/_kit/snippets/pyproject.tools.toml" >>"$PROJ/pyproject.toml"
  cp "$TPL/.pre-commit-config.yaml" "$PROJ/"
  # shellcheck disable=SC2016 # $1 and $2 expand in the child shell
  run --separate-stderr bash -c 'cd "$1" && node "$2"' _ "$PROJ" "$TPL/scripts/check/coverage-policy.mjs"
  [ "$status" -eq 0 ]
  sed 's/^fail_under = 100$/fail_under = 99/' "$PROJ/pyproject.toml" >"$PROJ/p" && mv "$PROJ/p" "$PROJ/pyproject.toml"
  # shellcheck disable=SC2016 # $1 and $2 expand in the child shell
  run --separate-stderr bash -c 'cd "$1" && node "$2"' _ "$PROJ" "$TPL/scripts/check/coverage-policy.mjs"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"fail_under is 99, must be 100"* ]] || false
}

@test "coverage-policy.mjs is the same bytes as every other stack's copy" {
  local other found=0
  for other in "$KIT_ROOT"/plugins/*/templates/*/scripts/check/coverage-policy.mjs; do
    [ -f "$other" ] || continue
    found=$((found + 1))
    cmp "$TPL/scripts/check/coverage-policy.mjs" "$other"
  done
  [ "$found" -ge 1 ]
}
