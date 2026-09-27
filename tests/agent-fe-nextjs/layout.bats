#!/usr/bin/env bats
# agent-fe-nextjs's layout and template invariants: what a plugin may ship, how its commands reach
# the templates, the setup.json schema, the pull-request-only CI templates, and the rule citations
# and context budget the installed files must satisfy.

load helpers

@test "the plugin root holds only plugin components (no bin/, no CLAUDE.md)" {
  run -0 python3 - "$PLUGIN" <<'PY'
import os, sys
root = sys.argv[1]
allowed = {".claude-plugin", "LICENSE", "README.md", "hooks", "scripts", "commands", "agents", "skills", "templates"}
extra = sorted(set(os.listdir(root)) - allowed)
assert not extra, f"unexpected entries at the plugin root: {extra}"
PY
}

@test "hooks.json runs generated-guard through bash, quoted CLAUDE_PLUGIN_ROOT, timeout 10" {
  run -0 python3 - "$PLUGIN" <<'PY'
import json, os, re, sys
root = sys.argv[1]
d = json.load(open(os.path.join(root, "hooks/hooks.json")))
seen = []
for event, entries in d["hooks"].items():
    assert event == "PreToolUse", event
    for e in entries:
        re.compile(e["matcher"])
        for h in e["hooks"]:
            m = re.fullmatch(r'bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/([a-z-]+\.sh)"', h["command"])
            assert m and h["type"] == "command", h
            assert h["timeout"] == 10 and isinstance(h["timeout"], int), h
            assert os.path.isfile(os.path.join(root, "scripts", m.group(1))), m.group(1)
            seen.append(m.group(1))
assert seen == ["generated-guard.sh"], seen
PY
}

@test "hook scripts are executable, and lib.sh is the same file as agent-core's" {
  for f in "$PLUGIN"/scripts/*.sh; do [ -x "$f" ]; done
  [ -f "$CORE/scripts/lib.sh" ] || skip "agent-core's scripts/lib.sh is not built yet"
  cmp "$PLUGIN/scripts/lib.sh" "$CORE/scripts/lib.sh"
}

@test "every command, agent and skill has frontmatter with a description; names match files" {
  run -0 python3 - "$PLUGIN" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
def front(path):
    t = open(path, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n", t, re.S)
    assert m, f"{path}: no frontmatter"
    return dict(re.findall(r"^([a-z-]+):\s*(.*)$", m.group(1), re.M)), t
for p in glob.glob(f"{root}/commands/**/*.md", recursive=True):
    f, t = front(p)
    assert f.get("description"), p
    if "$ARGUMENTS" in t:
        assert f.get("argument-hint"), f"{p}: takes $ARGUMENTS but has no argument-hint"
for p in glob.glob(f"{root}/agents/*.md"):
    f, _ = front(p)
    assert f.get("description") and f.get("name") == os.path.basename(p)[:-3], p
for p in glob.glob(f"{root}/skills/*/SKILL.md"):
    f, _ = front(p)
    assert f.get("description") and f.get("name") == os.path.basename(os.path.dirname(p)), p
PY
}

@test "no markdown link in a component reaches outside the plugin folder" {
  run -0 python3 - "$PLUGIN" <<'PY'
import glob, os, re, sys
root = os.path.realpath(sys.argv[1])
bad = []
for p in glob.glob(f"{root}/commands/**/*.md", recursive=True) + glob.glob(f"{root}/agents/*.md") + glob.glob(f"{root}/skills/**/*.md", recursive=True):
    for target in re.findall(r"\]\(([^)#\s]+)", open(p, encoding="utf-8").read()):
        if "://" in target:
            continue
        dest = os.path.realpath(os.path.join(os.path.dirname(p), target))
        if not dest.startswith(root + os.sep) or not os.path.exists(dest):
            bad.append(f"{os.path.relpath(p, root)} -> {target}")
assert not bad, bad
PY
}

@test "setup and sync pass the templates path quoted and never run apply unprompted" {
  for c in setup sync; do
    f="$PLUGIN/commands/$c.md"
    # The patterns are literal text to find in the markdown, so they stay in single quotes.
    # shellcheck disable=SC2016
    grep -q -- '--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs' "$f"
    # shellcheck disable=SC2016
    ! grep -nE '\$CLAUDE_PLUGIN_ROOT[^}]|\$CLAUDE_PLUGIN_ROOT$' "$f" || false
    allowed="$(sed -n 's/^allowed-tools: //p' "$f")"
    [ -n "$allowed" ]
    [[ "$allowed" != *apply* ]] || false
  done
}

@test "_kit/setup.json follows the engine's schema and every glob it names matches a template" {
  run -0 python3 - "$STACK_DIR" <<'PY'
import fnmatch, json, os, re, sys
stack = sys.argv[1]
d = json.load(open(os.path.join(stack, "_kit/setup.json")))
assert set(d) <= {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}, set(d)
assert d["stack"] == "fe-nextjs"
assert "agent-fe-nextjs-static" in d["conflictsWith"]
files = []
for dp, dn, fn in os.walk(stack):
    for n in fn:
        rel = os.path.relpath(os.path.join(dp, n), stack)
        if not rel.startswith("_kit" + os.sep):
            files.append(rel[:-len(".starter")] if rel.endswith(".starter") else rel)
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
def matches(glob):
    r = rx(glob)
    return [f for f in files if r.match(f)]
ids = set()
for q in d["questions"]:
    assert set(q) <= {"id", "ask", "why", "choices", "recommended", "detect", "install", "settings"}, q
    assert q["id"] not in ids; ids.add(q["id"])
    assert q["recommended"] in q["choices"] and q["ask"] and q["why"] and q["detect"], q["id"]
    for choice, globs in q.get("install", {}).items():
        assert choice in q["choices"], (q["id"], choice)
        for g in globs:
            assert matches(g), f"{q['id']}: install glob {g} matches no template"
for g in d["seed"]:
    assert matches(g), f"seed glob {g} matches no template"
for target, snippet in d["snippets"].items():
    assert os.path.isfile(os.path.join(stack, "_kit", snippet)), snippet
assert "unlock" not in d["packageScripts"], "unlock is declared once, in agent-core"
PY
}

@test "gitignore lines are sorted, hold no negation and repeat none of agent-core's" {
  # A sync of another plugin (agent-core's, an add-on's) renders this plugin's lines from the lock,
  # and the lock stores them sorted. Declared in that same order, both renders give the same block,
  # so the two syncs do not keep rewriting it; and with no "!x" line, sorting cannot move a
  # re-include ahead of the pattern it undoes. So each env file is named instead.
  run -0 python3 - "$STACK_DIR" "$CORE/templates/common" <<'PY'
import json, os, sys
stack, core = sys.argv[1], sys.argv[2]
mine = json.load(open(os.path.join(stack, "_kit/setup.json")))["gitignore"]
assert mine and len(mine) == len(set(mine)), mine
assert mine == sorted(mine), f"not in sorted order: {mine}"
assert not [l for l in mine if l.startswith("!") or not l.strip() or l.startswith("#")], mine
path = os.path.join(core, "_kit/setup.json")
if os.path.isfile(path):
    both = set(mine) & set(json.load(open(path))["gitignore"])
    assert not both, f"also in agent-core's gitignore lines: {sorted(both)}"
PY
}

@test "templates never ship what the kit forbids there" {
  run -0 python3 - "$STACK_DIR" <<'PY'
import json, os, sys
stack = sys.argv[1]
bad = []
for dp, dn, fn in os.walk(stack):
    for n in dn + fn:
        full = os.path.join(dp, n)
        rel = os.path.relpath(full, stack)
        if os.path.islink(full):
            bad.append(f"symlink {rel}")
        if n in ("package.json", ".gitignore", "CLAUDE.md", "AGENTS.md"):
            bad.append(f"forbidden file {rel}")
        if rel in (".claude/hooks", ".claude/commands", ".claude/agents", ".claude/skills"):
            bad.append(f"plugin component folder {rel}")
        if n.startswith(".env") and not n.endswith(".example"):
            bad.append(f"real env file {rel}")
s = json.load(open(os.path.join(stack, ".claude/settings.json")))
extra = set(s) - {"$schema", "permissions", "sandbox", "env", "extraKnownMarketplaces", "enabledPlugins"}
if extra:
    bad.append(f"settings.json keys {sorted(extra)}")
assert not bad, bad
for starter in ("CLAUDE.md.starter", "AGENTS.md.starter", "SSOT.md.starter"):
    assert os.path.isfile(os.path.join(stack, starter)), starter
PY
}

@test "no template duplicates a path agent-core's templates/common already ships" {
  [ -d "$CORE/templates/common" ] || skip "agent-core's templates/common is not built yet"
  run -0 python3 - "$STACK_DIR" "$CORE/templates/common" <<'PY'
import os, sys
mine, core = sys.argv[1], sys.argv[2]
def paths(root):
    out = set()
    for dp, dn, fn in os.walk(root):
        for n in fn:
            rel = os.path.relpath(os.path.join(dp, n), root)
            if not rel.startswith("_kit" + os.sep):
                out.add(rel)
    return out
dup = sorted((paths(mine) & paths(core)) - {".claude/settings.json"})
assert not dup, f"also in agent-core/templates/common: {dup}"
PY
}

@test "CI templates are pull-request only, least privilege and pinned to full SHAs" {
  run -0 python3 - "$STACK_DIR/.github/workflows" <<'PY'
import glob, re, sys
for p in sorted(glob.glob(sys.argv[1] + "/*.y*ml")):
    t = open(p, encoding="utf-8").read()
    for word in ("push:", "schedule:", "pull_request_target", "workflow_run", "workflow_dispatch", "secrets: inherit"):
        assert word not in t, f"{p}: {word}"
    assert re.search(r"^on:\n  pull_request:\n", t, re.M), f"{p}: trigger is not pull_request"
    assert re.search(r"^permissions:\n  contents: read\n", t, re.M), f"{p}: top-level permissions"
    uses = re.findall(r"^\s*(?:- )?uses: (\S+)(.*)$", t, re.M)
    assert uses, p
    for ref, rest in uses:
        assert re.search(r"@[0-9a-f]{40}$", ref) and re.match(r" # v\d+\.\d+\.\d+$", rest), f"{p}: {ref}{rest}"
    if "actions/checkout@" in t:
        assert "persist-credentials: false" in t, p
    for run in re.findall(r"run: (.*)", t):
        assert "${{" not in run, f"{p}: expression inside run"
PY
}

@test "gates.list names only package scripts setup adds and scripts the kit installs" {
  run -0 python3 - "$STACK_DIR" "$CORE/templates/common" <<'PY'
import json, os, re, sys
stack, core = sys.argv[1], sys.argv[2]
scripts = json.load(open(os.path.join(stack, "_kit/setup.json")))["packageScripts"]
for n, line in enumerate(open(os.path.join(stack, "scripts/check/gates.list"), encoding="utf-8"), 1):
    line = line.rstrip("\n")
    if not line.strip() or line.startswith("#"):
        continue
    kinds, tab, cmd = line.partition("\t")
    assert tab and kinds and cmd, f"line {n} is not <kinds><TAB><command>"
    assert set(kinds.split(",")) <= {"all", "code", "docs", "commands", "hooks"}, kinds
    m = re.fullmatch(r"bun run ([\w:-]+)", cmd)
    if m:
        assert m.group(1) in scripts, f"line {n}: package script {m.group(1)} is not in packageScripts"
        continue
    m = re.fullmatch(r"(?:bash|node|bun run) (\S+\.(?:sh|mjs|ts))(?: .*)?", cmd)
    if m:
        path = m.group(1)
        here = os.path.isfile(os.path.join(stack, path))
        there = os.path.isfile(os.path.join(core, path)) if os.path.isdir(core) else True
        assert here or there, f"line {n}: {path} ships nowhere"
PY
}

@test "every Rule number the installed files cite is defined in the AGENTS.md starter" {
  run -0 python3 - "$STACK_DIR" "$PLUGIN" <<'PY'
import glob, os, re, sys
stack, plugin = sys.argv[1], sys.argv[2]
agents = open(os.path.join(stack, "AGENTS.md.starter"), encoding="utf-8").read()
defined = set(re.findall(r"^[ \t]*(?:#{1,6}[ \t]+|[-*+][ \t]+|[0-9]+[.)][ \t]+)?(?:\*\*|__)?Rule ([0-9]+)(?:[^0-9].*)?$", agents, re.M))
defined |= set(re.findall(r"^[ \t]*\|[ \t]*(?:\*\*|__)?(?:Rule )?([0-9]+)(?:\*\*|__)?[ \t]*\|", agents, re.M))
citing = glob.glob(f"{stack}/.claude/**/*.md", recursive=True) + [f"{stack}/oxlint.json", f"{stack}/CLAUDE.md.starter", f"{stack}/SSOT.md.starter"]
citing += glob.glob(f"{plugin}/agents/*.md") + glob.glob(f"{plugin}/commands/*.md") + glob.glob(f"{plugin}/skills/**/*.md", recursive=True)
missing = []
for p in citing:
    for n in set(re.findall(r"Rule ([0-9]+)", open(p, encoding="utf-8").read())):
        if n not in defined:
            missing.append(f"{os.path.relpath(p, plugin)} cites Rule {n}")
assert not missing, missing
PY
}

@test "a fresh CLAUDE.md plus always-loaded rules stays inside the 15,000-byte budget" {
  run -0 python3 - "$STACK_DIR" "$CORE/templates/common" <<'PY'
import glob, os, re, sys
stack, core = sys.argv[1], sys.argv[2]
def no_paths(p):
    t = open(p, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n", t, re.S)
    return not (m and re.search(r"^paths:", m.group(1), re.M))
total = os.path.getsize(os.path.join(stack, "CLAUDE.md.starter"))
total += os.path.getsize(os.path.join(stack, "_kit/claude-md.md")) + 200  # markers and the ## heading
rules = glob.glob(f"{stack}/.claude/rules/**/*.md", recursive=True)
if os.path.isdir(core):
    rules += glob.glob(f"{core}/.claude/rules/**/*.md", recursive=True)
    frag = os.path.join(core, "_kit/claude-md.md")
    if os.path.isfile(frag):
        total += os.path.getsize(frag)
total += sum(os.path.getsize(p) for p in rules if no_paths(p))
print(total)
assert total < 15000, f"always-loaded context would be {total} bytes"
PY
}
