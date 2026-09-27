#!/usr/bin/env bats
# The files /agent-be-hono:setup installs, checked as data: the kit's template rules, the setup.json
# schema, rule citations, what gates.list calls, the CI caller's policy, and the commands' contract.

load helpers

setup() {
  be_setup_env
}

# py <<script: a Python check that prints "ok" when it holds, and the problems otherwise.
py() {
  run --separate-stderr python3 - "$KIT_ROOT"
  if [ "$status" -ne 0 ] || [ "$output" != ok ]; then
    printf '%s\n%s\n' "$output" "$stderr" >&2
    return 1
  fi
}

@test "every Rule N the plugin cites is defined in AGENTS.md.starter" {
  py <<'PY'
import glob, os, re, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-hono/templates/be-hono"
agents = open(f"{tpl}/AGENTS.md.starter", encoding="utf-8").read().splitlines()
# ai-config.sh's two definition shapes: a heading/bold/list lead "Rule N", or a table row whose
# first cell is N.
lead = re.compile(r"^\s*(#{1,6}\s+|[-*+]\s+|[0-9]+[.)]\s+)?(\*\*|__)?Rule ([0-9]+)([^0-9].*)?$")
row = re.compile(r"^\s*\|\s*(\*\*|__)?(Rule )?([0-9]+)(\*\*|__)?\s*\|.*$")
defined = {m.group(3) for line in agents for m in [lead.match(line) or row.match(line)] if m}
files = [os.path.join(d, n) for d, _, names in os.walk(tpl) for n in names
         if n.endswith((".md", ".starter", ".yml")) or n == ".oxlintrc.json"]
files += glob.glob(f"{root}/plugins/agent-be-hono/agents/*.md") + glob.glob(f"{root}/plugins/agent-be-hono/commands/*.md")
bad = []
for p in files:
    for n in sorted(set(re.findall(r"Rule ([0-9]+)", open(p, encoding="utf-8").read()))):
        if n not in defined:
            bad.append(f"{os.path.relpath(p, root)} cites Rule {n}")
assert len(defined) >= 40, sorted(defined)
assert len(files) >= 30, len(files)
print("\n".join(bad) if bad else "ok")
PY
}

@test "the template tree holds no path the kit forbids" {
  py <<'PY'
import os, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-hono/templates/be-hono"
bad = []
for d, dirs, files in os.walk(tpl):
    for name in dirs + files:
        p = os.path.join(d, name)
        rel = os.path.relpath(p, tpl)
        if os.path.islink(p):
            bad.append(f"symlink: {rel}")
        if name in ("package.json", ".gitignore", "CLAUDE.md", "AGENTS.md", "SSOT.md"):
            bad.append(f"forbidden file: {rel}")
        if name.startswith(".env") and not name.endswith(".example"):
            bad.append(f"real env file: {rel}")
        for comp in (".claude/hooks", ".claude/commands", ".claude/agents", ".claude/skills"):
            if rel == comp or rel.startswith(comp + "/"):
                bad.append(f"plugin component copied as a project file: {rel}")
kit = sorted(os.listdir(f"{tpl}/_kit"))
if kit != ["claude-md.md", "setup.json"]:
    bad.append(f"_kit holds {kit}")
print("\n".join(bad) if bad else "ok")
PY
}

@test "settings.json uses only the keys setup may merge, and never hooks" {
  py <<'PY'
import json, sys
root = sys.argv[1]
s = json.load(open(f"{root}/plugins/agent-be-hono/templates/be-hono/.claude/settings.json"))
allowed = {"$schema", "permissions", "sandbox", "env", "extraKnownMarketplaces", "enabledPlugins"}
assert set(s) <= allowed, set(s) - allowed
assert "hooks" not in json.dumps(s), "hooks"
assert s["permissions"]["allow"] == ["Bash(bun run test:*)", "Bash(bun run type-check:*)", "Bash(bun run lint:*)",
                                    "Bash(bun run format:*)", "Bash(bun run fl:*)", "Bash(bun run check:*)",
                                    "Bash(bun run db:generate:*)", "Bash(bun fl:*)", "Bash(bun test:*)"], s
assert s["permissions"]["deny"] == ["Edit(SSOT.md)", "Edit(AGENTS.md)"], s
print("ok")
PY
}

@test "setup.json follows the schema, and every glob in it matches a template file" {
  py <<'PY'
import json, os, re, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-hono/templates/be-hono"
s = json.load(open(f"{tpl}/_kit/setup.json"))
market = {p["name"] for p in json.load(open(f"{root}/.claude-plugin/marketplace.json"))["plugins"]}
bad = []
if set(s) != {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}:
    bad.append(f"keys {sorted(s)}")
if s["stack"] != "be-hono":
    bad.append("stack")
for c in s["conflictsWith"]:
    if c not in market or c == "agent-be-hono":
        bad.append(f"conflictsWith {c}")
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
        elif glob[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(glob[i]); i += 1
    return re.compile(out + r"\Z")
def hits(glob):
    return [f for f in files if rx(glob).match(f)]
ids = [q["id"] for q in s["questions"]]
if len(ids) != len(set(ids)):
    bad.append("duplicate question ids")
for q in s["questions"]:
    extra = set(q) - {"id", "ask", "why", "choices", "recommended", "detect", "install", "settings"}
    if extra or not {"id", "ask", "why", "choices", "recommended", "detect"} <= set(q):
        bad.append(f"{q.get('id')}: keys {sorted(q)}")
    if q["recommended"] not in q["choices"]:
        bad.append(f"{q['id']}: recommended not a choice")
    for choice, globs in q.get("install", {}).items():
        if choice not in q["choices"]:
            bad.append(f"{q['id']}: install for unknown choice {choice}")
        for g in globs:
            if not hits(g):
                bad.append(f"{q['id']}: install glob {g} matches nothing")
for g in s["seed"]:
    if not hits(g):
        bad.append(f"seed glob {g} matches nothing")
if "unlock" in s["packageScripts"]:
    bad.append("unlock is agent-core's alias")
# agent-core's engine renders a plugin it was not given from the lock, which stores these lines
# sorted: unsorted lines would read as a stale block, and a sorted "!" negation would land before
# the pattern it undoes. So the list is sorted and has no negation.
if s["gitignore"] != sorted(set(s["gitignore"])):
    bad.append("gitignore lines are not sorted and unique")
if any(line.startswith("!") for line in s["gitignore"]):
    bad.append("gitignore holds a negation")
if not all(isinstance(v, str) and v for v in s["packageScripts"].values()):
    bad.append("packageScripts values")
print("\n".join(bad) if bad else "ok")
PY
}

@test "gates.list calls only scripts and files a repo set up with agent-core and agent-be-hono has" {
  py <<'PY'
import json, os, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-hono/templates/be-hono"
core = f"{root}/plugins/agent-core/templates/common"
scripts = dict(json.load(open(f"{tpl}/_kit/setup.json"))["packageScripts"])
if os.path.exists(f"{core}/_kit/setup.json"):
    scripts.update(json.load(open(f"{core}/_kit/setup.json"))["packageScripts"])
def shipped(rel):
    return os.path.exists(f"{tpl}/{rel}") or os.path.exists(f"{core}/{rel}")
bad, lines = [], 0
for line in open(f"{tpl}/scripts/check/gates.list", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.startswith("#"):
        continue
    lines += 1
    kinds, _, cmd = line.partition("\t")
    if not cmd:
        bad.append(f"no TAB: {line!r}")
        continue
    words = cmd.split()
    if cmd == "@format":
        for s in ("format", "fl:ci"):
            if s not in scripts:
                bad.append(f"@format needs the {s} script")
    elif words[:2] == ["bun", "run"]:
        if words[2] not in scripts:
            bad.append(f"{cmd}: no {words[2]} script")
    elif words[0] == "bash":
        if not shipped(words[1]):
            bad.append(f"{cmd}: {words[1]} is not installed")
    elif words[0] == "gitleaks":
        if not shipped(".gitleaks.toml"):
            bad.append("gitleaks config")
    else:
        bad.append(f"unknown gate {cmd}")
# Every script a package script runs by path is installed too.
for name, value in scripts.items():
    for word in value.split():
        if word.startswith("scripts/") and not shipped(word):
            bad.append(f"package script {name} runs {word}, which is not installed")
assert lines >= 10, lines
print("\n".join(bad) if bad else "ok")
PY
}

@test "gates.list runs no gate that passes on nothing in plugin mode (hook probes, command mirror)" {
  # A repo set up from the plugins has no .claude/hooks/ and no _workflow-source/: both scripts
  # would print "skipping" and exit 0.
  run grep -nE 'hook-probes\.sh|ai-config-probes\.sh|workflows\.sh' "$TPL/scripts/check/gates.list"
  [ "$status" -eq 1 ]
}

@test "template scripts keep the source's exec bit; data files have none" {
  [ -x "$TPL/scripts/check/ci-env.sh" ]
  [ -x "$TPL/scripts/check/index-coverage.sh" ]
  [ -x "$TPL/scripts/check/migrations.sh" ]
  run find "$TPL" -type f -perm -u+x ! -name ci-env.sh ! -name index-coverage.sh ! -name migrations.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every rule loads by path, so none adds to the always-loaded budget" {
  py <<'PY'
import glob, sys
root = sys.argv[1]
bad = []
for p in sorted(glob.glob(f"{root}/plugins/agent-be-hono/templates/be-hono/.claude/rules/**/*.md", recursive=True)):
    text = open(p, encoding="utf-8").read()
    head = text.split("\n---\n", 1)[0] if text.startswith("---\n") else ""
    if "\npaths:" not in "\n" + head:
        bad.append(p)
print("\n".join(bad) if bad else "ok")
PY
}

@test "CLAUDE.md starter plus the managed block stays inside the 15,000-byte always-loaded budget" {
  py <<'PY'
import glob, os, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-hono/templates/be-hono"
core = f"{root}/plugins/agent-core/templates/common"
# The block's markers and heading (about 140 bytes), and 300 bytes of headroom for the user.
size = os.path.getsize(f"{tpl}/CLAUDE.md.starter") + os.path.getsize(f"{tpl}/_kit/claude-md.md") + 140 + 300
for frag in glob.glob(f"{core}/_kit/claude-md.md"):
    size += os.path.getsize(frag)
for rule in glob.glob(f"{core}/.claude/rules/**/*.md", recursive=True):
    text = open(rule, encoding="utf-8").read()
    if not (text.startswith("---\n") and "\npaths:" in text.split("\n---\n", 1)[0]):
        size += len(text.encode())
print("ok" if size <= 15000 else f"always-loaded {size} bytes")
PY
}

@test "the managed CLAUDE.md fragment is short and has no heading above ###" {
  run grep -nE '^#{1,2} ' "$TPL/_kit/claude-md.md"
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$TPL/_kit/claude-md.md")" -le 12 ]
  head -1 "$TPL/_kit/claude-md.md" | grep -q '^### '
}

@test "the starters point only at files setup installs (or at .example files to copy)" {
  py <<'PY'
import os, re, sys
root = sys.argv[1]
tpl = f"{root}/plugins/agent-be-hono/templates/be-hono"
core = f"{root}/plugins/agent-core/templates/common"
def exists(rel):
    for base in (tpl, core):
        if os.path.exists(f"{base}/{rel}") or os.path.exists(f"{base}/{rel}.starter"):
            return True
        stem, ext = os.path.splitext(rel)
        if os.path.exists(f"{base}/{stem}.example{ext}"):
            return True
    return False
bad = []
names = ["CLAUDE.md.starter", "AGENTS.md.starter", "SSOT.md.starter", ".claude/docs/code-review-checklist.md",
         ".claude/rules/common/testing.md", ".claude/rules/common/patterns.md", ".claude/rules/backend/drizzle.md",
         ".claude/rules/backend/testing.md", ".claude/rules/backend/hono.md", ".claude/rules/backend/performance.md"]
for name in names:
    text = open(f"{tpl}/{name}", encoding="utf-8").read()
    for ref in sorted(set(re.findall(r"`((?:\.claude|scripts|docs|\.github|\.husky)/[^`\s*<>]+)`", text))):
        ref = ref.rstrip("/.,")
        if ref.endswith("/"):
            continue
        if not exists(ref) and not os.path.isdir(f"{tpl}/{ref}") and not os.path.isdir(f"{core}/{ref}"):
            bad.append(f"{name}: {ref}")
print("\n".join(bad) if bad else "ok")
PY
}

@test "no template-mode leftovers in what the plugin ships" {
  # The backticks are literal: the pattern matches a bare template command in Markdown.
  # shellcheck disable=SC2016
  run grep -rnE 'agents-reviewer|\.claude/hooks/|strip-ai-on-pr|strip-paths\.sh|`/(review|ship|checkpoint|promote)`' \
    "$TPL" "$PLUGIN/agents"
  [ "$status" -eq 1 ]
  # The commands may name .claude/hooks/ (to explain double wiring), never a bare template command.
  # shellcheck disable=SC2016
  run grep -rnE 'agents-reviewer|strip-ai-on-pr|`/(review|ship|checkpoint|promote)`' "$PLUGIN/commands"
  [ "$status" -eq 1 ]
}

@test "the CI caller is pull-request only, least privilege, and pinned to a full SHA" {
  py <<'PY'
import re, sys
root = sys.argv[1]
text = open(f"{root}/plugins/agent-be-hono/templates/be-hono/.github/workflows/quality-gate.yml").read()
bad = []
on = re.search(r"^on:\n((?:  .*\n|\s*\n)+)", text, re.M).group(1)
triggers = re.findall(r"^  ([a-z_]+):", on, re.M)
if triggers != ["pull_request"]:
    bad.append(f"triggers {triggers}")
if not re.search(r"^permissions:\n  contents: read\n", text, re.M):
    bad.append("top-level permissions")
uses = re.findall(r"uses: (\S+)(.*)", text)
if not uses:
    bad.append("no uses")
for ref, comment in uses:
    if not re.fullmatch(r"[\w.-]+/[\w.-]+(/[\w./-]+)?@[0-9a-f]{40}", ref) or not re.fullmatch(r" # v\d+\.\d+\.\d+", comment):
        bad.append(f"unpinned {ref}{comment}")
    if "be-hono-quality-gate.yml" not in ref:
        bad.append(f"calls {ref}")
for word in ("secrets: inherit", "run:", "schedule", "push:", "pull_request_target", "workflow_run", "workflow_dispatch"):
    if word in text:
        bad.append(word)
print("\n".join(bad) if bad else "ok")
PY
}

@test "setup and sync pass the templates path explicitly and leave apply to a permission prompt" {
  local f
  # The ${CLAUDE_PLUGIN_ROOT} in these patterns is literal text in the command files.
  # shellcheck disable=SC2016
  for f in "$PLUGIN/commands/setup.md" "$PLUGIN/commands/sync.md"; do
    grep -q -- '--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-hono' "$f"
    run grep -nE '\$CLAUDE_PLUGIN_ROOT[^}]' "$f"
    [ "$status" -eq 1 ]
    run grep -nE '^allowed-tools:.*apply' "$f"
    [ "$status" -eq 1 ]
    grep -q '^description: ' "$f"
  done
  grep -q '^argument-hint: ' "$PLUGIN/commands/setup.md"
  grep -q 'Reply \*\*go\*\* to write exactly this' "$PLUGIN/commands/setup.md"
}

@test "the reviewer agent has a name and a description, and cites the starter's rules" {
  head -5 "$PLUGIN/agents/reviewer.md" | grep -q '^name: reviewer$'
  head -5 "$PLUGIN/agents/reviewer.md" | grep -q '^description: '
  grep -q '/agent-be-hono:setup' "$PLUGIN/agents/reviewer.md"
  grep -q 'No AGENTS.md violations found in this diff.' "$PLUGIN/agents/reviewer.md"
}
