#!/usr/bin/env bats
# agent-fe-nextjs-static's layout and template invariants: what the plugin ships, how its commands
# reach the templates, what setup may install, the gate list and package scripts it names, the
# pull-request-only CI caller, and the cross-references between its files.

load helpers

@test "the plugin root holds only commands, agents and templates (no hooks, scripts or bin)" {
  run -0 python3 - "$PLUGIN" <<'PY'
import os, sys
root = sys.argv[1]
allowed = {".claude-plugin", "LICENSE", "README.md", "commands", "agents", "templates"}
extra = sorted(set(os.listdir(root)) - allowed)
assert not extra, f"unexpected entries at the plugin root: {extra}"
for dirpath, dirs, files in os.walk(root):
    for n in dirs + files:
        assert not os.path.islink(os.path.join(dirpath, n)), f"symlink: {os.path.join(dirpath, n)}"
PY
}

@test "every command and agent has frontmatter; commands reach the templates the documented way" {
  run -0 python3 - "$PLUGIN" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
def front(path):
    t = open(path, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n", t, re.S)
    assert m, f"{path}: no frontmatter"
    return dict(re.findall(r"^([a-z-]+):\s*(.*)$", m.group(1), re.M)), t
commands = sorted(os.path.basename(p)[:-3] for p in glob.glob(f"{root}/commands/*.md"))
agents = sorted(os.path.basename(p)[:-3] for p in glob.glob(f"{root}/agents/*.md"))
assert commands == ["a11y-audit", "launch-checklist", "review", "seo-audit", "setup", "sync"], commands
assert agents == ["i18n-guard", "security-guard", "seo-validator"], agents
for p in glob.glob(f"{root}/commands/*.md"):
    f, t = front(p)
    assert f.get("description"), p
    if "$ARGUMENTS" in t:
        assert f.get("argument-hint"), f"{p}: takes $ARGUMENTS but has no argument-hint"
    assert not re.search(r"\$CLAUDE_PLUGIN_ROOT(?!\})", t.replace("${CLAUDE_PLUGIN_ROOT}", "")), f"{p}: unbraced CLAUDE_PLUGIN_ROOT"
    body = t.split("\n---\n", 1)[1]
    # An invocation carries flags; "Run `agent-setup plan` with every answer" is prose.
    calls = [c for c in re.findall(r"(?:^|`)(agent-(?:setup|sync) (?:questions|plan|apply|check|own)[^\n`]*)", body, re.M) if " --" in c]
    if os.path.basename(p) in ("setup.md", "sync.md"):
        assert calls, f"{p}: no agent-setup/agent-sync invocation found"
    for call in calls:
        assert '--templates "${CLAUDE_PLUGIN_ROOT}/templates"' in call and "--stack fe-nextjs-static" in call, f"{p}: {call}"
    tools = f.get("allowed-tools", "")
    assert "apply" not in tools, f"{p}: apply must stay out of allowed-tools"
for p in glob.glob(f"{root}/agents/*.md"):
    f, _ = front(p)
    assert f.get("description") and f.get("name") == os.path.basename(p)[:-3], p
    assert "Edit" not in f.get("tools", "") and "Write" not in f.get("tools", ""), f"{p}: a reviewer agent never edits"
# Every namespaced reference names a component that exists.
text = "".join(open(p, encoding="utf-8").read() for p in glob.glob(f"{root}/**/*.md", recursive=True))
for c in set(re.findall(r"/agent-fe-nextjs-static:([a-z0-9-]+)", text)):
    assert c in commands, f"/agent-fe-nextjs-static:{c} is not a command"
for a in set(re.findall(r"(?<![/\w])agent-fe-nextjs-static:([a-z0-9-]+)", text)):
    assert a in agents or a in commands, f"agent-fe-nextjs-static:{a} is neither an agent nor a command"
PY
}

@test "every file, rule, anti-pattern and check a plugin file names exists" {
  run -0 python3 - "$PLUGIN" "$CORE/templates/common" <<'PY'
import os, re, sys
root, common = sys.argv[1], sys.argv[2]
stack = os.path.join(root, "templates", "fe-nextjs-static")
def exists(rel):
    return any(os.path.exists(os.path.join(base, cand)) for base in (stack, common) for cand in (rel, rel + ".starter"))
# os.walk, not glob('**'): glob skips dot-folders such as .claude/.
files = [os.path.join(d, n) for d, _, ns in os.walk(root) for n in ns
         if n.endswith((".md", ".starter", ".mjs", ".json", ".list", ".yaml"))]
assert any("/.claude/rules/" in f for f in files), "the walk must reach .claude/"
names = {n for d, _, ns in os.walk(os.path.join(stack, ".claude")) for n in ns}
missing, refs = set(), 0
for p in files:
    t = open(p, encoding="utf-8").read()
    for ref in re.findall(r"(?<![\w/.-])((?:\.claude/(?:rules|anti-patterns)/[\w./-]+\.md)|(?:scripts/(?:check|env|ops)/[\w./-]+\.(?:mjs|sh|json|list))|docs/unlock\.md)", t):
        refs += 1
        if not exists(ref):
            missing.add(f"{os.path.relpath(p, root)} -> {ref}")
    # A bare `name.md` in a rule or an anti-pattern names a sibling rule or anti-pattern.
    if "/.claude/" in p:
        for name in re.findall(r"`([a-z0-9-]+\.md)`", t):
            refs += 1
            if name not in names and name not in ("AGENTS.md", "SSOT.md", "CLAUDE.md"):
                missing.add(f"{os.path.relpath(p, root)} -> {name}")
assert refs > 50, refs
assert not missing, "\n".join(sorted(missing))
PY
}

@test "templates: nothing a plugin must not install, and settings.json carries no hooks" {
  run -0 python3 - "$PLUGIN_TEMPLATES/fe-nextjs-static" <<'PY'
import json, os, re, sys
stack = sys.argv[1]
bad = []
for dirpath, dirs, files in os.walk(stack):
    for n in files:
        rel = os.path.relpath(os.path.join(dirpath, n), stack).replace(os.sep, "/")
        if rel.startswith("_kit/"):
            continue
        dest = rel[:-len(".starter")] if rel.endswith(".starter") else rel
        if n == ".gitignore" or dest == "package.json":
            bad.append(rel)
        if dest.startswith((".claude/hooks/", ".claude/commands/", ".claude/agents/", ".claude/skills/")):
            bad.append(rel)
        if dest in ("CLAUDE.md", "AGENTS.md") and not rel.endswith(".starter"):
            bad.append(rel)
        if re.match(r"\.env(rc)?([._-]|$)", n) and not n.endswith(".example"):
            bad.append(rel)
assert not bad, bad
s = json.load(open(os.path.join(stack, ".claude/settings.json")))
assert set(s) <= {"$schema", "permissions", "sandbox", "env", "extraKnownMarketplaces", "enabledPlugins"}, set(s)
assert "hooks" not in s
PY
}

@test "setup.json: every install and seed glob matches a template, and packageScripts name real files" {
  run -0 python3 - "$PLUGIN_TEMPLATES/fe-nextjs-static" <<'PY'
import fnmatch, json, os, re, sys
stack = sys.argv[1]
cfg = json.load(open(os.path.join(stack, "_kit/setup.json")))
assert set(cfg) <= {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}, set(cfg)
assert cfg["stack"] == "fe-nextjs-static"
assert sorted(cfg["conflictsWith"]) == ["agent-ai-fastapi", "agent-be-hono", "agent-docs-nextra", "agent-fe-nextjs"]
dests = []
for dirpath, _, files in os.walk(stack):
    for n in files:
        rel = os.path.relpath(os.path.join(dirpath, n), stack).replace(os.sep, "/")
        if not rel.startswith("_kit/"):
            dests.append(rel[:-len(".starter")] if rel.endswith(".starter") else rel)
def glob_re(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i): out, i = out + "(?:.*/)?", i + 3; continue
        if g.startswith("**", i): out, i = out + ".*", i + 2; continue
        out += {"*": "[^/]*", "?": "[^/]"}.get(g[i], re.escape(g[i])); i += 1
    return re.compile(out + r"\Z")
def hits(g): return [d for d in dests if glob_re(g).match(d)]
for q in cfg["questions"]:
    assert q["recommended"] in q["choices"], q["id"]
    for choice, globs in q.get("install", {}).items():
        for g in globs:
            assert hits(g), f"question {q['id']}={choice}: {g} matches no template"
for g in cfg["seed"]:
    assert hits(g), f"seed {g} matches no template"
assert "unlock" not in cfg["packageScripts"]
for name, cmd in cfg["packageScripts"].items():
    for ref in re.findall(r"scripts/check/[\w./-]+\.mjs", cmd):
        assert ref in dests, f"packageScripts.{name} runs {ref}, which setup does not install"
PY
}

@test "gates.list: TAB-separated known kinds, and every command it runs is installed or scripted" {
  run -0 python3 - "$PLUGIN_TEMPLATES/fe-nextjs-static" "$CORE/templates/common" <<'PY'
import json, os, re, sys
stack, common = sys.argv[1], sys.argv[2]
scripts = json.load(open(os.path.join(stack, "_kit/setup.json")))["packageScripts"]
for line in open(os.path.join(stack, "scripts/check/gates.list")):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    kinds, cmd = line.split("\t", 1)
    assert set(kinds.split(",")) <= {"all", "code", "docs", "commands", "hooks"}, line
    m = re.match(r"(?:node|bash) (scripts/check/[\w./-]+)", cmd)
    if m:
        assert os.path.exists(os.path.join(stack, m.group(1))) or os.path.exists(os.path.join(common, m.group(1))), line
    m = re.match(r"npm run --silent ([\w:-]+)", cmd)
    if m:
        assert m.group(1) in scripts, f"gates.list runs {m.group(1)}, which setup does not add"
    if cmd == "@format":
        assert "format" in scripts and "fl:ci" in scripts
PY
}

@test "the CI caller is pull-request only, least privilege, and pins the reusable workflow" {
  run -0 python3 - "$PLUGIN_TEMPLATES/fe-nextjs-static/.github/workflows/quality-gate.yaml" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
body = "\n".join(l for l in t.splitlines() if not l.lstrip().startswith("#"))
on = re.search(r"^on:\n((?:[ \t]+.*\n)+)", body + "\n", re.M).group(1)
events = re.findall(r"^  ([a-z_]+):", on, re.M)
assert events == ["pull_request"], events
for banned in ("push:", "schedule:", "pull_request_target", "workflow_run", "workflow_dispatch", "secrets: inherit"):
    assert banned not in body, banned
assert re.search(r"^permissions:\n  contents: read$", body, re.M)
uses = re.findall(r"uses: (\S+)(.*)", body)
assert uses, "no uses:"
for ref, comment in uses:
    assert re.search(r"@[0-9a-f]{40}$", ref), ref
    assert re.search(r"# v\d+\.\d+\.\d+", comment), comment
assert "adhibuchori/agent-config-kit/.github/workflows/fe-nextjs-static-quality-gate.yml@" in uses[0][0]
PY
}

@test "every rule loads only with matching files, and the anti-pattern index matches its files" {
  run -0 python3 - "$PLUGIN_TEMPLATES/fe-nextjs-static/.claude" <<'PY'
import glob, os, re, sys
base = sys.argv[1]
for p in glob.glob(f"{base}/rules/**/*.md", recursive=True):
    t = open(p).read()
    m = re.match(r"---\npaths:\n((?:  - '[^']+'\n)+)---\n", t)
    assert m, f"{p}: needs a paths: list so it is not always loaded"
files = {os.path.basename(p) for p in glob.glob(f"{base}/anti-patterns/*.md")} - {"INDEX.md"}
rows = set(re.findall(r"\|\s*([a-z0-9-]+\.md)\s*\|", open(f"{base}/anti-patterns/INDEX.md").read()))
assert rows == files, (sorted(rows - files), sorted(files - rows))
for f in files:
    t = open(f"{base}/anti-patterns/{f}").read()
    assert "**Applies to:**" in t and "**Status:**" in t, f
PY
}

@test "config files parse, and the budgets say what the rules promise" {
  run -0 python3 - "$PLUGIN_TEMPLATES/fe-nextjs-static" <<'PY'
import json, os, re, sys
stack = sys.argv[1]
def jsonc(p):
    t = re.sub(r"^\s*//.*$", "", open(p).read(), flags=re.M)
    return json.loads(t)
ox = jsonc(os.path.join(stack, "oxlint.json"))
for r in ("react/no-danger", "nextjs/no-img-element", "jsx-a11y/alt-text"):
    assert ox["rules"].get(r) == "error", r
assert "jsx-a11y" in ox["plugins"] and "nextjs" in ox["plugins"]
jsonc(os.path.join(stack, ".oxfmtrc.json"))
json.load(open(os.path.join(stack, "knip.json")))
lh = json.load(open(os.path.join(stack, "lighthouserc.json")))["ci"]
a = lh["assert"]["assertions"]
assert a["largest-contentful-paint"] == ["error", {"maxNumericValue": 2500}]
assert a["cumulative-layout-shift"] == ["error", {"maxNumericValue": 0.1}]
assert a["total-blocking-time"] == ["error", {"maxNumericValue": 200}]
assert lh["upload"]["target"] == "filesystem", "reports stay on disk"
assert "scripts/check/serve.mjs" in lh["collect"]["startServerCommand"]
cfg = json.load(open(os.path.join(stack, "scripts/check/site.config.json")))
assert cfg["fonts"]["maxFamilies"] == 2 and cfg["mode"] == "auto" and cfg["headersFile"] == "public/_headers"
PY
}

@test "every check script parses, documents its usage, and site-audit runs only checks that exist" {
  for f in "$CHECKS"/*.mjs "$CHECKS"/lib/*.mjs; do node --check "$f"; done
  for f in "$CHECKS"/*.mjs; do grep -q "^//   node scripts/check/$(basename "$f")" "$f"; done
  run -0 python3 - "$CHECKS" <<'PY'
import os, re, sys
d = sys.argv[1]
names = re.findall(r"\['([a-z-]+)', \[", open(os.path.join(d, "site-audit.mjs")).read())
assert len(names) == 10, names
for n in names:
    assert os.path.isfile(os.path.join(d, f"{n}.mjs")), n
PY
}

@test "the fixture holds no binary files and no real hosts" {
  run -0 python3 - "$FIXTURE" <<'PY'
import os, re, sys
bad = []
for dirpath, _, files in os.walk(sys.argv[1]):
    for n in files:
        p = os.path.join(dirpath, n)
        data = open(p, "rb").read()
        if b"\0" in data:
            bad.append(f"binary: {p}")
        for host in re.findall(rb"https?://([a-z0-9.-]+)", data):
            h = host.decode()
            if not re.search(r"(^|\.)example\.(com|org|net)$|^localhost$|^127\.0\.0\.1$|^schema\.org$|^www\.w3\.org$|^www\.sitemaps\.org$", h):
                bad.append(f"host {h}: {p}")
assert not bad, bad
PY
}
