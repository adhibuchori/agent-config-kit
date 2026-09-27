#!/usr/bin/env bats
# shellcheck disable=SC2016 # single-quoted patterns are the literal shell text searched for
# agent-core's hooks/hooks.json and the files it runs: the wiring rules of the kit (quoted
# ${CLAUDE_PLUGIN_ROOT}, run through bash, explicit timeouts, `|| true` only where a failure must
# not erase the prompt), matchers that reach the tools they are meant for, and runtime code that
# never downloads or opens the network.

load ../helpers/common

@test "every hook command runs a plugin script through bash with a quoted \${CLAUDE_PLUGIN_ROOT} and the kit's timeout" {
  python3 - "$CORE" <<'PY'
import json, os, re, sys
core = sys.argv[1]
wiring = json.load(open(os.path.join(core, "hooks", "hooks.json")))
assert isinstance(wiring.get("description"), str) and wiring["description"], "hooks.json needs a description"
timeouts = {"post-commit.sh": 20, "post-edit.sh": 60}
seen = []
for event, groups in wiring["hooks"].items():
    for group in groups:
        for hook in group["hooks"]:
            cmd = hook["command"]
            m = re.fullmatch(r'bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/([a-z-]+\.sh)"( \|\| true)?', cmd)
            assert m, f"{event}: {cmd}"
            name, or_true = m.group(1), bool(m.group(2))
            assert hook["type"] == "command", hook
            assert type(hook["timeout"]) is int and hook["timeout"] == timeouts.get(name, 10), (name, hook["timeout"])
            # Only SessionStart and UserPromptSubmit swallow failures; a guard never does.
            assert or_true == (event in ("SessionStart", "UserPromptSubmit")), (event, cmd)
            path = os.path.join(core, "scripts", name)
            assert os.path.isfile(path) and os.access(path, os.X_OK), f"{name} missing or not executable"
            seen.append(name)
scripts = sorted(n for n in os.listdir(os.path.join(core, "scripts")) if n.endswith(".sh") and n != "lib.sh")
assert sorted(seen) == scripts, f"wired {sorted(seen)} but scripts/ holds {scripts}"
print("ok", len(seen))
PY
}

@test "the matchers reach the tools each hook is for, and no other" {
  python3 - "$CORE/hooks/hooks.json" <<'PY'
import json, re, sys
wiring = json.load(open(sys.argv[1]))
by_script = {}
for event, groups in wiring["hooks"].items():
    for group in groups:
        for hook in group["hooks"]:
            name = re.search(r"scripts/([a-z-]+)\.sh", hook["command"]).group(1)
            by_script[(event, name)] = group.get("matcher")
def reaches(event, name, tool):
    m = by_script[(event, name)]
    return m is None or re.fullmatch(m, tool) is not None
cases = {
    ("PreToolUse", "safety-check"): (["Bash"], ["BashOutput", "Write", "mcp__x__bash"]),
    ("PreToolUse", "db-guard"): (["mcp__db-prod__execute_sql", "mcp__pg__query", "mcp__serena__find_symbol"], ["Bash", "Write"]),
    ("PreToolUse", "mcp-guard"): (["mcp__github__push_files", "mcp__github__create_or_update_file", "mcp__github__delete_file",
                                   "mcp__github__create_branch", "mcp__plugin_github_github__push_files"],
                                  ["mcp__github__get_file_contents", "mcp__github__merge_pull_request", "Bash"]),
    ("PostToolUse", "post-commit"): (["Bash"], ["Write"]),
    ("PostToolUse", "post-edit"): (["Write", "Edit", "MultiEdit", "mcp__serena__replace_symbol_body", "mcp__serena__rename_symbol"],
                                   ["Bash", "Read", "mcp__serena__find_symbol"]),
}
for key, (yes, no) in cases.items():
    for tool in yes:
        assert reaches(*key, tool), (key, tool)
    for tool in no:
        assert not reaches(*key, tool), (key, tool)
for key in [("SessionStart", "session-start"), ("SessionStart", "setup-check"), ("UserPromptSubmit", "prompt-intent")]:
    assert by_script[key] is None, key
PY
}

@test "every hook script parses under /bin/bash, is shellcheck-clean, and sources the lib.sh beside it" {
  for f in "$HOOKS"/*.sh "$CORE"/bin/*; do
    /bin/bash -n "$f"
  done
  if command -v shellcheck >/dev/null; then
    (cd "$HOOKS" && shellcheck -x -S style ./*.sh)
    shellcheck -S style "$CORE"/bin/*
  fi
  for f in "$HOOKS"/*.sh; do
    [ "$(basename "$f")" = lib.sh ] && continue
    grep -qx 'source "$(dirname "${BASH_SOURCE\[0\]}")/lib.sh"' "$f" || { echo "$f does not source its lib.sh" >&2; return 1; }
  done
}

@test "every plugin that ships a lib.sh ships the same bytes as agent-core's" {
  for lib in "$KIT_ROOT"/plugins/*/scripts/lib.sh; do
    cmp "$HOOKS/lib.sh" "$lib"
  done
}

@test "the plugin's runtime code never downloads or opens the network" {
  python3 - "$CORE" <<'PY'
import os, re, sys
core = sys.argv[1]
word = re.compile(r"\b(curl|wget|npx|bunx|uvx|pipx|pip3? install|npm install|nc|ncat|telnet)\b|urllib|http\.client|socket\b")
bad = []
paths = [os.path.join(core, d, n) for d in ("scripts", "bin", "libexec") for n in sorted(os.listdir(os.path.join(core, d)))]
for path in paths:
    for no, line in enumerate(open(path, encoding="utf-8"), 1):
        if not word.search(line):
            continue
        text = line.strip()
        # lib.sh names package runners as data its command parser recognises, and in comments.
        if os.path.basename(path) == "lib.sh" and (text.startswith("#") or '"' in text or "'" in text):
            continue
        bad.append(f"{os.path.relpath(path, core)}:{no}: {text}")
assert not bad, "\n".join(bad)
PY
}

@test "bin/ and every hook script are executable; the engine is plain data run by python3 -I" {
  for f in "$CORE"/bin/* "$HOOKS"/*.sh; do
    [ -x "$f" ] || { echo "$f is not executable" >&2; return 1; }
  done
  grep -q 'exec python3 -I "$root/libexec/agentkit.py" setup "$@"' "$CORE/bin/agent-setup"
  grep -q 'exec python3 -I "$root/libexec/agentkit.py" sync "$@"' "$CORE/bin/agent-sync"
  python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$CORE/libexec/agentkit.py"
  # Standard library only: every import is a module python3 ships.
  python3 - "$CORE/libexec/agentkit.py" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
stdlib = getattr(sys, "stdlib_module_names", None) or {"argparse", "copy", "hashlib", "json", "os", "re", "stat", "subprocess", "sys"}
assert mods <= set(stdlib), mods - set(stdlib)
PY
}
