#!/usr/bin/env bats
# templates/be-axum as data: the setup.json contract, the paths a template may never hold, the
# permissions, the CI callers, the gate list, the rule index and its citations, the starter and its
# snippet, the shared copies, and the seeded skeleton's own limits.

load helpers

setup() {
  ax_setup_env
}

# py <<script: a Python check that prints "ok" when it holds, and the problems otherwise.
py() {
  run --separate-stderr python3 - "$KIT_ROOT"
  if [ "$status" -ne 0 ] || [ "$output" != ok ]; then
    printf '%s\n%s\n' "$output" "$stderr" >&2
    return 1
  fi
}

template_paths() {
  (cd "$TPL" && find . -path ./_kit -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' | sort)
}

@test "setup.json: this stack, the known keys, valid answers, and the seven other primary stacks" {
  py <<'PY'
import json, sys
s = json.load(open(f"{sys.argv[1]}/plugins/agent-be-axum/templates/be-axum/_kit/setup.json"))
bad = []
if set(s) != {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}:
    bad.append(f"keys {sorted(s)}")
if s["stack"] != "be-axum":
    bad.append("stack")
if s["conflictsWith"] != ["agent-ai-fastapi", "agent-be-go", "agent-be-hono", "agent-docs-nextra",
                          "agent-fe-nextjs", "agent-fe-nextjs-static", "agent-ios-swiftui"]:
    bad.append(f"conflictsWith {s['conflictsWith']}")
ids = [q["id"] for q in s["questions"]]
if ids != ["migrations", "ci-gate", "deepseek-review", "pr-templates", "analytics", "serena-workspace"]:
    bad.append(f"questions {ids}")
for q in s["questions"]:
    if q["recommended"] not in q["choices"] or not set(q.get("install", {})) <= set(q["choices"]):
        bad.append(f"question {q['id']}")
if s["packageScripts"] != {} or s["snippets"] != {"Cargo.toml": "snippets/cargo.toml"}:
    bad.append("packageScripts or snippets")
print("\n".join(bad) if bad else "ok")
PY
}

@test "every install and seed glob names at least one template file" {
  py <<'PY'
import json, os, re, sys
tpl = f"{sys.argv[1]}/plugins/agent-be-axum/templates/be-axum"
s = json.load(open(f"{tpl}/_kit/setup.json"))
files = []
for d, _, names in os.walk(tpl):
    for n in names:
        rel = os.path.relpath(os.path.join(d, n), tpl)
        if not rel.startswith("_kit/"):
            files.append(rel[: -len(".starter")] if rel.endswith(".starter") else rel)
def rx(glob):
    out, i = "", 0
    while i < len(glob):
        if glob.startswith("**", i):
            out += ".*"; i += 2
        elif glob[i] == "*":
            out += "[^/]*"; i += 1
        else:
            out += re.escape(glob[i]); i += 1
    return re.compile(out + r"\Z")
globs = [g for q in s["questions"] for gs in q.get("install", {}).values() for g in gs] + s["seed"]
bad = [g for g in globs if not any(rx(g).match(f) for f in files)]
print("\n".join(f"matches nothing: {g}" for g in bad) if bad else "ok")
PY
}

@test "no path a template may never hold, no symlink, no cache file" {
  run template_paths
  [ "${#lines[@]}" -gt 60 ]
  local p
  for p in "${lines[@]}"; do
    case "$p" in
    package.json | */package.json | .gitignore | */.gitignore | Cargo.lock) false ;;
    .claude/hooks/* | .claude/commands/* | .claude/agents/* | .claude/skills/*) false ;;
    CLAUDE.md | AGENTS.md | Cargo.toml) false ;;
    .env | .env.* | */.env | */.env.*) [[ "$p" == *.example ]] ;;
    esac
  done
  run find "$TPL" \( -type l -o -name target -o -name .DS_Store -o -name '._*' -o -name coverage \) -print
  [ -z "$output" ]
}

@test "settings.json: named commands only; a runner, an install or an upgrade asks first" {
  py <<'PY'
import json, re, sys
s = json.load(open(f"{sys.argv[1]}/plugins/agent-be-axum/templates/be-axum/.claude/settings.json"))
bad = []
if set(s) != {"$schema", "permissions"}:
    bad.append(f"keys {sorted(s)}")
allow, ask = s["permissions"]["allow"], s["permissions"]["ask"]
broad = re.compile(r"^Bash\((cargo|cargo run|cargo install|cargo add|cargo update|bash|sh|node|npx|sqlx)(:\*|\s\*)?\)$")
for rule in allow:
    if broad.match(rule) or re.match(r"^Bash\(cargo (run|install|add|update)\b", rule):
        bad.append(f"broad allow {rule}")
for rule in ("Bash(cargo run:*)", "Bash(cargo install:*)", "Bash(cargo add:*)", "Bash(cargo update:*)"):
    if rule not in ask:
        bad.append(f"{rule} not in ask")
for rule in allow:
    if re.match(r"^Bash\(cargo (clippy|check|test|nextest|llvm-cov|tree)\b", rule) and "--locked" not in rule:
        bad.append(f"{rule} without --locked")
if s["permissions"]["deny"] != ["Edit(AGENTS.md)"]:
    bad.append("deny")
print("\n".join(bad) if bad else "ok")
PY
}

@test "the CI callers: pull requests only, read-only, pinned by full SHA" {
  local f
  for f in quality-gate deepseek-review; do
    f="$TPL/.github/workflows/$f.yml"
    run grep -nE '^[[:space:]]*(push|schedule|pull_request_target|workflow_run|workflow_dispatch):' "$f"
    [ "$status" -eq 1 ]
    run grep -E '^[[:space:]]*uses:' "$f"
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" =~ uses:\ adhibuchori/agent-config-kit/\.github/workflows/[a-z-]+\.yml@[0-9a-f]{40}\ \#\ v[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
  done
  grep -q 'be-axum-quality-gate.yml@' "$TPL/.github/workflows/quality-gate.yml"
  run bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -nE "write|secrets|inherit|run:"' _ "$TPL/.github/workflows/quality-gate.yml"
  [ "$status" -eq 1 ]
}

@test "gates.list runs only scripts this stack or agent-core installs, and every cargo call is --locked" {
  local s
  while IFS= read -r s; do
    [ -e "$TPL/$s" ] || [ -e "$CORE_TPL/$s" ] || {
      echo "no plugin installs $s" >&2
      return 1
    }
  done < <(grep -ohE 'scripts/check/[A-Za-z0-9_.-]+\.(sh|mjs)' "$TPL/scripts/check/gates.list" | sort -u)
  run grep -E '^[a-z,]+	cargo ' "$TPL/scripts/check/gates.list"
  [ "${#lines[@]}" -ge 1 ]
  run grep -E '^[a-z,]+	cargo (build|check|clippy|test|nextest|llvm-cov)' "$TPL/scripts/check/gates.list"
  [[ "$output" != *$'\n'* ]] || false
  [[ "$output" == *"--locked"* ]] || false
  grep -qx 'bash scripts/check/gates.sh --hook --fail-fast' "$TPL/.githooks/pre-commit"
  [ -x "$TPL/.githooks/pre-commit" ]
}

@test "AGENTS.md.starter defines rules 1 to 29, each with an enforcer, and every cited rule exists" {
  py <<'PY'
import glob, os, re, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-axum/templates/be-axum"
text = open(f"{tpl}/AGENTS.md.starter", encoding="utf-8").read()
rows = [l for l in text.split("\n## Rules\n", 1)[1].splitlines() if re.match(r"^\| [0-9]+ \|", l)]
numbers = [int(l.split("|")[1]) for l in rows]
bad = []
if numbers != list(range(1, 30)):
    bad.append(f"rules {numbers}")
for l in rows:
    cells = [c.strip() for c in l.strip().strip("|").split("|")]
    if len(cells) != 4 or not all(cells):
        bad.append(f"row {cells[0]} lacks a cell")
    elif not os.path.isfile(os.path.join(tpl, cells[3].strip("`"))):
        bad.append(f"row {cells[0]} points at {cells[3]}, which the template does not ship")
files = [os.path.join(d, n) for d, _, names in os.walk(tpl) for n in names if n.endswith((".md", ".starter", ".yml", ".toml"))]
files += glob.glob(f"{root}/plugins/agent-be-axum/agents/*.md") + glob.glob(f"{root}/plugins/agent-be-axum/skills/*/*.md")
for p in files:
    for n in set(re.findall(r"Rule ([0-9]+)", open(p, encoding="utf-8").read())):
        if int(n) not in numbers:
            bad.append(f"{os.path.relpath(p, root)} cites Rule {n}")
print("\n".join(bad) if bad else "ok")
PY
}

@test "every rule file loads by path, and the anti-pattern index lists every file" {
  local f name
  for f in "$TPL"/.claude/rules/*/*.md; do
    [ "$(head -1 "$f")" = "---" ]
    sed -n '2,/^---$/p' "$f" | grep -q '^paths:'
  done
  for f in "$TPL"/.claude/anti-patterns/*.md; do
    name="$(basename "$f")"
    [ "$name" = INDEX.md ] && continue
    grep -qF "| $name |" "$TPL/.claude/anti-patterns/INDEX.md" || {
      echo "INDEX.md does not list $name" >&2
      return 1
    }
  done
  [ "$(find "$TPL/.claude/anti-patterns" -name '*.md' ! -name INDEX.md | wc -l | tr -d ' ')" -eq 20 ]
}

@test "the cargo.toml snippet is the starter's lint and profile block, word for word" {
  local starter snippet
  starter="$(sed -n '/^# >>> agent-be-axum/,/^# <<< agent-be-axum/p' "$TPL/Cargo.toml.starter")"
  snippet="$(sed -n '/^# >>> agent-be-axum/,/^# <<< agent-be-axum/p' "$TPL/_kit/snippets/cargo.toml")"
  [ -n "$starter" ]
  [ "$starter" = "$snippet" ]
  grep -qx 'overflow-checks = true # release builds otherwise wrap where the tests panic' <<<"$starter"
  grep -qx 'panic = "unwind"' <<<"$starter"
}

@test "the toolchain, rust-version, config and lint files agree" {
  grep -qx 'channel = "1.99.0"' "$TPL/rust-toolchain.toml"
  grep -qx 'components = \["clippy", "rustfmt", "llvm-tools"\]' "$TPL/rust-toolchain.toml"
  grep -q '^rust-version = "1.99"' "$TPL/Cargo.toml.starter"
  grep -qx 'warnings = "deny".*' "$TPL/.cargo/config.toml"
  grep -qx 'SQLX_OFFLINE = "true".*' "$TPL/.cargo/config.toml"
  grep -q 'slow-timeout = { period = "30s", terminate-after = 2 }' "$TPL/.config/nextest.toml"
  grep -q 'path = "tower_http::timeout::TimeoutLayer::new"' "$TPL/clippy.toml"
  grep -q 'path = "std::env::var"' "$TPL/clippy.toml"
}

@test "the seeded spec publishes the base error.rs holds, and the code enum inline" {
  py <<'PY'
import json, re, sys
tpl = f"{sys.argv[1]}/plugins/agent-be-axum/templates/be-axum"
spec = json.load(open(f"{tpl}/openapi.json"))
base = re.search(r'PROBLEM_TYPE_BASE: &str = "([^"]+)"', open(f"{tpl}/src/platform/error.rs").read()).group(1)
problem = spec["components"]["schemas"]["Problem"]
bad = []
if base != "https://example.invalid/problems/":
    bad.append(f"placeholder base {base}")
if problem["properties"]["type"].get("x-problem-type-base") != base:
    bad.append("x-problem-type-base")
if problem["properties"]["type"].get("format") != "uri":
    bad.append("format")
codes = problem["properties"]["code"].get("enum", [])
if "ROUTE_NOT_FOUND" not in codes or any(not re.fullmatch(r"[A-Z][A-Z0-9_]*", c) for c in codes):
    bad.append(f"codes {codes}")
print("\n".join(bad) if bad else "ok")
PY
}

@test "the seeded Rust stays within 200 lines of code per file, and every exemption has its reason" {
  command -v node >/dev/null || skip "node not installed"
  local line
  while IFS=$'\t' read -r count file; do
    [ "$count" -le 200 ] || {
      echo "$file holds $count lines of code" >&2
      return 1
    }
  done < <(find "$TPL/src" "$TPL/tests" -name '*.rs' -print0 | xargs -0 node "$TPL/scripts/check/rust-source.mjs" --count)
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    [[ "$line" =~ ^[^#]+[[:space:]]#[[:space:]]composition\ root:\ .+ ]] || false
  done <"$TPL/scripts/check/coverage-exempt.txt"
}

@test "the shared check scripts are the same bytes as their sources" {
  cmp "$TPL/scripts/check/coverage-policy.mjs" "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/coverage-policy.mjs"
  cmp "$TPL/scripts/check/ci-env.sh" "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/ci-env.sh"
  local other
  for other in "$KIT_ROOT"/plugins/*/templates/*/scripts/check/coverage-per-file.mjs; do
    cmp "$TPL/scripts/check/coverage-per-file.mjs" "$other"
  done
}

@test "the CLAUDE.md fragment is short, names the reviewer, and has no heading above ###" {
  local f="$TPL/_kit/claude-md.md"
  run grep -nE '^#{1,2} ' "$f"
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$f")" -le 12 ]
  grep -q 'agent-be-axum:reviewer' "$f"
  [ "$(wc -c <"$TPL/CLAUDE.md.starter")" -le 700 ]
}

@test "no path agent-core's templates/common already ships" {
  local p
  while IFS= read -r p; do
    [ ! -e "$CORE_TPL/$p" ] || {
      echo "duplicates agent-core: $p" >&2
      return 1
    }
  done < <(template_paths | grep -vx '.claude/settings.json')
}

@test "the PostgreSQL files shared with agent-be-go are the same bytes as its copies" {
  local go="$KIT_ROOT/plugins/agent-be-go/templates/be-go" f
  [ -d "$go" ] || skip "agent-be-go is not in this tree yet"
  for f in db/roles.sql .claude/rules/backend/postgres.md .claude/anti-patterns/cached-plan-after-schema-change.md \
    .claude/anti-patterns/cic-inside-transaction.md .claude/anti-patterns/cic-retry-keeps-invalid-index.md \
    .claude/anti-patterns/ddl-without-lock-timeout.md .claude/anti-patterns/default-privileges-without-for-role.md \
    .claude/anti-patterns/enum-value-used-in-same-transaction.md \
    .claude/anti-patterns/pgbouncer-rejects-startup-parameters.md \
    .claude/anti-patterns/read-only-default-is-not-a-boundary.md \
    .claude/anti-patterns/session-state-behind-transaction-pooler.md .claude/anti-patterns/unindexed-foreign-keys.md; do
    [ -f "$TPL/$f" ]
    cmp "$TPL/$f" "$go/$f"
  done
}
