#!/usr/bin/env bats
# What agent-docs-nextra's setup installs: the template tree, its _kit/setup.json, and the CI
# callers, held to the kit's rules (docs: cd conventions §5-§7 and §12).

load helpers

@test "the plugin carries exactly its components, and no CLAUDE.md or bin/" {
  [ -f "$DN_PLUGIN/hooks/hooks.json" ]
  [ -f "$DN_PLUGIN/commands/setup.md" ]
  [ -f "$DN_PLUGIN/commands/sync.md" ]
  [ -f "$DN_PLUGIN/agents/seo-validator.md" ]
  [ -f "$DN_PLUGIN/agents/security-guard.md" ]
  [ ! -e "$DN_PLUGIN/CLAUDE.md" ]
  [ ! -e "$DN_PLUGIN/bin" ]
  [ -x "$DN_PLUGIN/scripts/generated-guard.sh" ]
  [ -x "$DN_PLUGIN/scripts/lib.sh" ]
}

@test "commands pass the templates path written out, and keep apply out of allowed-tools" {
  local f
  for f in "$DN_PLUGIN/commands/setup.md" "$DN_PLUGIN/commands/sync.md"; do
    # shellcheck disable=SC2016 # the literal text the command markdown must carry
    grep -q -- '--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack docs-nextra' "$f"
    # shellcheck disable=SC2016 # a regex for the unbraced variable, not an expansion
    run ! grep -Eq '\$CLAUDE_PLUGIN_ROOT[^}]' "$f"
    run -0 awk '/^---$/{n++; next} n==1 && /^allowed-tools:/' "$f"
    [[ "$output" == allowed-tools:* ]] || false
    [[ "$output" != *apply* ]] || false
    [[ "$output" != *" own"* ]] || false
  done
  grep -q 'Reply \*\*go\*\* to write exactly this' "$DN_PLUGIN/commands/setup.md"
  grep -q -- '--digest sha256:' "$DN_PLUGIN/commands/setup.md"
}

@test "agents are report-only: no write tools" {
  local f
  for f in "$DN_PLUGIN"/agents/*.md; do
    run -0 awk '/^---$/{n++; next} n==1 && /^tools:/' "$f"
    [[ "$output" == "tools: Read, Grep, Glob, Bash" ]] || false
    grep -q '^name: ' "$f"
    grep -q '^description: .*Reports findings; changes nothing' "$f"
  done
}

@test "_kit/setup.json follows the engine's schema, and every glob names a shipped file" {
  run python3 - "$DN_STACK" <<'PY'
import fnmatch, json, os, re, sys
root = sys.argv[1]
cfg = json.load(open(os.path.join(root, "_kit/setup.json")))
assert set(cfg) <= {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}, cfg.keys()
assert cfg["stack"] == "docs-nextra"
assert "unlock" not in cfg["packageScripts"], "unlock is agent-core's alias"
assert sorted(cfg["conflictsWith"]) == ["agent-ai-fastapi", "agent-be-hono", "agent-fe-nextjs", "agent-fe-nextjs-static"]
assert not any(line.startswith("!") for line in cfg["gitignore"]), "a negation depends on line order"
dests = []
for d, _, fs in os.walk(root):
    for f in fs:
        rel = os.path.relpath(os.path.join(d, f), root)
        if not rel.startswith("_kit/"):
            dests.append(rel[:-8] if rel.endswith(".starter") else rel)
def glob_re(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**", i): out, i = out + ".*", i + 2
        elif g[i] == "*": out, i = out + "[^/]*", i + 1
        elif g[i] == "?": out, i = out + "[^/]", i + 1
        else: out, i = out + re.escape(g[i]), i + 1
    return re.compile(out + r"\Z")
def hits(g): return [p for p in dests if glob_re(g).match(p)]
ids = set()
for q in cfg["questions"]:
    assert set(q) <= {"id", "ask", "why", "choices", "recommended", "detect", "install", "settings"}, q.keys()
    assert q["id"] not in ids; ids.add(q["id"])
    assert q["recommended"] in q["choices"], q["id"]
    for choice, globs in q.get("install", {}).items():
        assert choice in q["choices"], (q["id"], choice)
        for g in globs:
            assert hits(g), f"install glob {g} matches nothing"
for g in cfg["seed"]:
    assert hits(g), f"seed glob {g} matches nothing"
print(len(cfg["questions"]), "questions,", len(dests), "template files")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "5 questions,"* ]] || false
}

@test "the template tree holds nothing the kit forbids" {
  run python3 - "$DN_STACK" <<'PY'
import json, os, sys
root = sys.argv[1]
bad = []
for d, dirs, fs in os.walk(root):
    for name in dirs + fs:
        p = os.path.join(d, name); rel = os.path.relpath(p, root)
        if os.path.islink(p): bad.append(("symlink", rel))
        if rel.startswith((".claude/hooks", ".claude/commands", ".claude/agents", ".claude/skills")):
            bad.append(("plugin component", rel))
        if name in ("package.json", ".gitignore", "CLAUDE.md", "AGENTS.md"): bad.append(("never installed", rel))
        if name.startswith(".env") and not name.endswith(".example"): bad.append(("real env file", rel))
settings = json.load(open(os.path.join(root, ".claude/settings.json")))
if "hooks" in settings: bad.append(("hooks key", ".claude/settings.json"))
extra = set(settings) - {"$schema", "permissions", "sandbox", "env", "extraKnownMarketplaces", "enabledPlugins"}
if extra: bad.append(("settings keys", sorted(extra)))
print(bad or "clean")
PY
  [ "$status" -eq 0 ]
  [ "$output" = clean ]
}

@test "plugin mode leaves no pointer to a template-only file" {
  run grep -rnE 'docs/RATIONALE\.md|strip-ai|_workflow-source|\.claude/hooks/|sync/workflows\.sh|SETUP\.md|/promote-deploy' "$DN_STACK" "$DN_PLUGIN/agents"
  [ "$status" -eq 1 ]
  # setup.md names .claude/hooks/ only to find a copied template's wiring (double wiring).
  run grep -rnE 'docs/RATIONALE\.md|strip-ai|_workflow-source|sync/workflows\.sh|SETUP\.md|/promote-deploy' "$DN_PLUGIN/commands"
  [ "$status" -eq 1 ]
}

@test "file modes follow the sources: only the shell check is executable" {
  run find "$DN_STACK" -type f -perm -u+x
  [ "$status" -eq 0 ]
  [ "$output" = "$DN_STACK/.github/scripts/check-comment-blocks.sh" ]
}

@test "nothing duplicates agent-core's templates/common, and shared paths elsewhere are identical or conflicting" {
  [[ -d "$DN_CORE/templates/common" ]] || skip "agent-core's templates are not built yet"
  run python3 - "$DN_REPO" <<'PY'
import glob, hashlib, json, os, sys
repo = sys.argv[1]
def tree(root):
    out = {}
    for d, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(d, f); rel = os.path.relpath(p, root)
            if rel.startswith("_kit/") or rel == ".claude/settings.json":
                continue
            out[rel[:-8] if rel.endswith(".starter") else rel] = hashlib.sha256(open(p, "rb").read()).digest()
    return out
mine_root = os.path.join(repo, "plugins/agent-docs-nextra/templates/docs-nextra")
mine = tree(mine_root)
conflicts = set(json.load(open(os.path.join(mine_root, "_kit/setup.json")))["conflictsWith"])
problems = []
for tdir in sorted(glob.glob(os.path.join(repo, "plugins/*/templates/*"))):
    plugin = tdir.split(os.sep)[-3]
    if plugin == "agent-docs-nextra":
        continue
    other = tree(tdir)
    for p in sorted(set(mine) & set(other)):
        if plugin == "agent-core":
            problems.append(("duplicates agent-core", p))
        elif mine[p] != other[p] and plugin not in conflicts:
            problems.append((plugin, p))
print(problems or "clean")
PY
  [ "$status" -eq 0 ]
  [ "$output" = clean ]
}

@test "every script gates.list runs is installed by this plugin or by agent-core" {
  run python3 - "$DN_STACK" "$DN_CORE/templates/common" <<'PY'
import os, re, sys
stack, core = sys.argv[1], sys.argv[2]
missing, n = [], 0
for line in open(os.path.join(stack, "scripts/check/gates.list")):
    if not line.strip() or line.startswith("#"):
        continue
    kinds, cmd = line.rstrip("\n").split("\t")
    n += 1
    for path in re.findall(r"(?:scripts|\.github)/[\w./-]+\.(?:sh|ts|mjs)", cmd):
        if not any(os.path.exists(os.path.join(base, path)) for base in (stack, core)):
            missing.append(path)
print(n, "gates;", missing or "all present")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"all present" ]] || false
  run ! grep -Eq 'hook-probes|ai-config-probes|sync/workflows' "$DN_STACK/scripts/check/gates.list"
}

@test "CI templates are pull-request only, least privilege and pinned to full SHAs" {
  run python3 - "$DN_STACK/.github/workflows" <<'PY'
import os, re, sys
wdir = sys.argv[1]
ALLOWED = {"pull_request", "workflow_call"}
# The documented exceptions (ADR 0004): the changelog also runs on the app's release event, and the
# DeepSeek review on an /ask-deepseek comment (scripts/workflow-policy.py checks its safe shape).
EXTRA = {"changelog.yaml": {"repository_dispatch"}, "deepseek-review.yml": {"issue_comment"}}
problems = []
for name in sorted(os.listdir(wdir)):
    lines = open(os.path.join(wdir, name)).read().split("\n")
    # Triggers: the keys indented two spaces under the top-level `on:`.
    i = lines.index("on:")
    triggers = set()
    for l in lines[i + 1:]:
        if l and not l.startswith(" "):
            break
        m = re.match(r"^  ([a-z_]+):", l)
        if m:
            triggers.add(m.group(1))
    if not triggers or triggers - ALLOWED - EXTRA.get(name, set()):
        problems.append((name, "triggers", sorted(triggers)))
    j = lines.index("permissions:")
    if lines[j + 1].strip() != "contents: read" or (lines[j + 2].startswith("  ") and lines[j + 2].strip()):
        problems.append((name, "top-level permissions"))
    uses = [l.split("uses:", 1)[1].strip() for l in lines if re.match(r"^\s*(- )?uses:", l)]
    for u in uses:
        if not (u.startswith("./") or re.fullmatch(r"[\w.-]+/[\w./-]+@[0-9a-f]{40} # v\d+(\.\d+)*", u)):
            problems.append((name, "unpinned", u))
    checkouts = sum(1 for u in uses if u.startswith("actions/checkout@"))
    if sum(1 for l in lines if l.strip() == "persist-credentials: false") < checkouts:
        problems.append((name, "persist-credentials"))
    if any(l.strip() == "secrets: inherit" for l in lines):
        problems.append((name, "secrets: inherit"))
    # No expression inside a run: script, single-line or block.
    k = 0
    while k < len(lines):
        m = re.match(r"^(\s*)(- )?run:\s*(.*)$", lines[k])
        if m:
            indent, rest = len(m.group(1)), m.group(3)
            if "${{" in rest:
                problems.append((name, "expression in run", k + 1))
            if rest.startswith(("|", ">")):
                k += 1
                while k < len(lines) and (not lines[k].strip() or len(lines[k]) - len(lines[k].lstrip()) > indent):
                    if "${{" in lines[k]:
                        problems.append((name, "expression in run", k + 1))
                    k += 1
                continue
        k += 1
print(problems or "clean")
PY
  [ "$status" -eq 0 ]
  [ "$output" = clean ]
}

@test "the gate caller pins agent-config-kit's reusable docs-nextra workflow and passes no secrets" {
  local f="$DN_STACK/.github/workflows/quality-gate.yaml"
  grep -Eq '^    uses: adhibuchori/agent-config-kit/\.github/workflows/docs-nextra-quality-gate\.yml@[0-9a-f]{40} # v1\.0\.0$' "$f"
  run ! grep -Eq '^[[:space:]]*secrets:' "$f"
  grep -q '^  pull_request:$' "$f"
}

@test "CLAUDE.md starter and fragment fit the always-loaded budget" {
  [ -f "$DN_STACK/CLAUDE.md.starter" ]
  run -0 grep -c '' "$DN_STACK/_kit/claude-md.md"
  [ "$output" -le 12 ]
  run ! grep -Eq '^#{1,2} ' "$DN_STACK/_kit/claude-md.md"
  run ! grep -q '^@' "$DN_STACK/CLAUDE.md.starter"
  local bytes
  bytes=$(($(wc -c <"$DN_STACK/CLAUDE.md.starter") + $(wc -c <"$DN_STACK/_kit/claude-md.md")))
  # ai-config.sh holds CLAUDE.md plus the always-loaded rules to 15,000 bytes; working-agreements.md
  # (agent-core) is under 5 KB, so starter plus fragment stay under 10,000.
  [ "$bytes" -lt 10000 ]
}
