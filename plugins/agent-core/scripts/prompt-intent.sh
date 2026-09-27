#!/usr/bin/env bash
# UserPromptSubmit: prunes the hooks' per-session state of sessions idle for two days, and points a
# /debug shorthand at this project's /rca command when the project has one (as a plugin, at
# /agent-core:rca otherwise). It reads no permission
# from the prompt: a hard rule stays refused whoever asks, and the user runs a refused command
# themselves with `!`. Wire it on UserPromptSubmit only, with `|| true`: an exit 2 here would erase
# the user's prompt. Fails open: without python3, or with a payload it cannot read, it says nothing.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start feedback "[prompt-intent]"

read -r -d '' PROGRAM <<'PY'
import json, os, re, shutil, sys, time

data = json.loads(sys.stdin.buffer.read() or b"{}")
if data.get("hook_event_name") != "UserPromptSubmit":
    sys.exit(0)
sid = data.get("session_id") or ""
state = os.environ["STATE_DIR"]
if sid:
    # Only folders that look like a session's state, so a state dir pointed somewhere unexpected
    # loses nothing else. Never this session: its folder's time is refreshed, because rewriting a
    # file inside it does not change the folder's own mtime.
    for d in os.listdir(state) if os.path.isdir(state) else []:
        path = os.path.join(state, d)
        try:
            if (d != sid and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", d) and os.path.isdir(path)
                    and set(os.listdir(path)) <= {"heads"} and time.time() - os.path.getmtime(path) > 2 * 86400):
                shutil.rmtree(path)
        except OSError:
            pass
    os.makedirs(os.path.join(state, sid), exist_ok=True)
    os.utime(os.path.join(state, sid))

root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
# The project's own /rca first; installed as a plugin, agent-core's /agent-core:rca otherwise.
plugin = os.environ.get("CLAUDE_PLUGIN_ROOT") or ""
if os.path.isfile(os.path.join(root, ".claude", "commands", "rca.md")):
    rca, where = "rca", "this project's /rca command"
elif plugin and os.path.isfile(os.path.join(plugin, "commands", "rca.md")):
    rca, where = "agent-core:rca", "the /agent-core:rca command"
else:
    rca = where = ""
low, notes = (data.get("prompt") or "").lower(), []
if rca and re.search(r"(^|\s)/(debug|rca)(?![\w:/.-])", low):
    notes.append(f"The user's /debug means {where}, a reproduction-first debugging protocol: "
                 f"load it with the Skill tool (skill `{rca}`). The built-in `debug` skill debugs Claude Code itself, not this project.")
if notes:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": " ".join(notes)}}))
PY

printf '%s' "$HOOK_INPUT" | PYTHONIOENCODING=utf-8:surrogateescape STATE_DIR="$(hook_state_dir)" python3 -c "$PROGRAM" 2>/dev/null
exit 0
