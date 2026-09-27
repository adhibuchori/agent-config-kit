# shellcheck shell=bash
# Shared by every bats file under tests/: paths into the kit, an isolated git identity, temp repo
# builders, and hook payload helpers. Load with `load ../helpers/common`.
#
# HOOK_BASH picks the bash that runs the hooks (default /bin/bash, which is 3.2 on macOS, so the
# suite proves bash 3.2 there). No test needs the network; every fixture lives in a bats temp dir.
bats_require_minimum_version 1.5.0

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CORE="$KIT_ROOT/plugins/agent-core"
# agent-core's version, as setup and sync print it.
CORE_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$CORE/.claude-plugin/plugin.json")"
HOOKS="$CORE/scripts"
TEMPLATES="$CORE/templates"
COMMON="$TEMPLATES/common"
HOOK_BASH="${HOOK_BASH:-/bin/bash}"
[ -x "$HOOK_BASH" ] || HOOK_BASH="$(command -v bash)"
export KIT_ROOT CORE CORE_VERSION HOOKS TEMPLATES COMMON HOOK_BASH

# The environment every hook run starts from: none of the caller's git, plugin or workspace state.
kit_isolate() { # $1 a folder for the git config and hook state
  unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  unset AGENT_WORKSPACE_ROOT CLAUDE_ENV_FILE HOOK_PROBE_CRASH HOOK_PROBE_NO_TEMP HOOK_PROBE_CAP
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR npm_config_user_agent
  mkdir -p "$1"
  cat >"$1/gitconfig" <<'EOF'
[user]
	email = probe@example.invalid
	name = probe
[commit]
	gpgsign = false
[init]
	defaultBranch = main
EOF
  export GIT_CONFIG_GLOBAL="$1/gitconfig" GIT_CONFIG_NOSYSTEM=1
  export AGENT_HOOK_STATE_DIR="$1/hook-state"
}

# $1 dir, $2 branch (default main): a git repo with one empty commit.
new_repo() {
  git init -q -b "${2:-main}" "$1" && git -C "$1" commit -q --allow-empty -m init
}

# JSON payloads, built by python3 so any quoting survives. \n is a newline and \t a tab.
bash_payload() { # $1 cwd, $2 command, [$3 tool_use_id]
  python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "tool_use_id": sys.argv[3], "cwd": sys.argv[1], "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[2].replace("\\n", "\n").replace("\\t", "\t")}}))' "$1" "$2" "${3:-}"
}
tool_payload() { # $1 tool name, $2 tool_input as a JSON object
  python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2])}))' "$1" "$2"
}
sql_payload() { # $1 tool, $2 SQL
  python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": {"sql": sys.argv[2]}}))' "$1" "$2"
}

# $1 hook file name, $2 payload, then VAR=value pairs: runs the hook the way Claude Code does, the
# payload on stdin. Use it under `run --separate-stderr`.
hook() {
  local name="$1" payload="$2"
  shift 2
  printf '%s' "$payload" | env "$@" "$HOOK_BASH" "$HOOKS/$name"
}

# PATH folders holding only what the hooks may call: nopy (jq, no python3), nojq (python3, no jq),
# nojson (neither). Printed as the folder to put on PATH.
tool_kit() { # $1 nopy|nojq|nojson, $2 parent folder
  local kit="$1" dir="$2/$1" tool p
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for tool in bash cat dirname basename sed paste grep awk tr sort comm head sleep git env mkdir rm touch jq python3; do
      case "$kit:$tool" in nopy:python3 | nojq:jq | nojson:jq | nojson:python3) continue ;; esac
      p="$(command -v "$tool" 2>/dev/null)" && ln -sf "$p" "$dir/$tool"
    done
  fi
  printf '%s' "$dir"
}

# The project the safety-check probe table is judged in (hook-probes.tsv header), under $1.
probe_fixture() {
  local tmp="$1" p="$1/proj" f
  new_repo "$p" feature/probe
  mkdir -p "$p/notes" "$p/docs" "$p/build"
  echo keep >"$p/notes/keep.txt" && echo a >"$p/docs/a.md" && printf '[alembic]\n' >"$p/alembic.ini"
  echo out >"$p/build/out.txt"
  printf '.env\n.env.local\n.claude/state/\n' >"$p/.gitignore"
  printf 'API_KEY=\n' >"$p/.env.example" && printf 'API_KEY=\n' >"$p/.env.production.example"
  cat >"$p/package.json" <<'EOF'
{"scripts": {"unlock": "bash scripts/ops/unlock.sh", "u2": "bash scripts/ops/unlock.sh", "dump": "cat .env", "build": "echo build"}}
EOF
  mkdir -p "$p/scripts/ops" "$p/scripts/env" "$p/scripts/check"
  for f in scripts/ops/unlock.sh scripts/env/show.sh scripts/env/set.sh scripts/check/gates.sh; do printf '#!/bin/sh\n' >"$p/$f"; done
  printf '\n' >"$p/scripts/env/envfile.py"
  git -C "$p" add notes docs scripts alembic.ini .gitignore .env.example .env.production.example package.json
  git -C "$p" commit -q -m fixture
  printf 'API_KEY=probe-secret-value\n' >"$p/.env" && printf 'API_KEY=probe-local-value\n' >"$p/.env.local"
  mkdir -p "$tmp/forged/.claude/state/unlock" "$tmp/plain-tree/sub"
  printf '4102444800\n' >"$tmp/forged/.claude/state/unlock/env" && cp "$tmp/forged/.claude/state/unlock/env" "$tmp/token"
  echo x >"$tmp/plain-tree/sub/x.txt"
  tar -cf "$tmp/forged.tar" -C "$tmp/forged" .claude && tar -cf "$tmp/plain.tar" -C "$tmp" plain-tree
  # shellcheck disable=SC2016 # the $1 belongs to the script written
  mkdir -p "$tmp/forged-helpers/scripts/env" && printf '#!/bin/sh\ncat "$1"\n' >"$tmp/forged-helpers/scripts/env/show.sh"
}

# $1 temp folder, $2 branch: a fixture repo checked out on that branch (hook-probes.tsv "checkout").
probe_branch() {
  local d="$1/on-${2//\//-}"
  [ -d "$d" ] || new_repo "$d" "$2"
  printf '%s' "$d"
}

# One row of hook-probes.tsv: $1 block|allow|warn, $2 - or a branch, $3 the command. Reads
# FIX_TMP (the temp folder) and FIX_PROJ (the fixture project).
# shellcheck disable=SC2154 # status, output and stderr are set by bats' run
probe() {
  local expect="$1" spec="$2" cmd="${3//@TMP@/$FIX_TMP}" cwd="$FIX_PROJ" got=allow
  [ "$spec" = - ] || cwd="$FIX_TMP/on-${spec//\//-}"
  run --separate-stderr hook safety-check.sh "$(bash_payload "$cwd" "$cmd")" CLAUDE_PROJECT_DIR="$FIX_PROJ"
  [ "$status" -eq 2 ] && got=block
  [ "$status" -eq 0 ] && [[ "$output" == *additionalContext* ]] && got=warn
  [ "$status" -ne 0 ] && [ "$status" -ne 2 ] && got="error $status"
  if [ "$got" != "$expect" ]; then
    printf 'expected %s, got %s\ncommand: %s\nstdout: %s\nstderr: %s\n' "$expect" "$got" "$cmd" "$output" "$stderr" >&2
    return 1
  fi
}

# The engine, from a kit checkout: the same program Claude Code runs from the plugin's bin/.
# ENGINE_CORE picks another agent-core folder (a copy an upgrade test changed); ARGS holds the
# --templates/--stack/--project flags of the plugin under test (core_args or stack_args sets it).
setup_cli() { "${ENGINE_CORE:-$CORE}/bin/agent-setup" "$@"; }
sync_cli() { "${ENGINE_CORE:-$CORE}/bin/agent-sync" "$@"; }

# The digest line of a plan's output.
digest_of() { awk '/^digest /{ print $2 }' <<<"$1"; }

# $1 project: ARGS for agent-core's own layer (templates/common), from ENGINE_CORE or the checkout.
core_args() {
  ARGS=(--templates "${ENGINE_CORE:-$CORE}/templates" --stack common --project "$1")
}
# $1 plugin folder, $2 stack id, $3 project.
stack_args() {
  ARGS=(--templates "$1/templates" --stack "$2" --project "$3")
}

# plan, then apply with the digest the plan printed; extra arguments are --answer flags.
setup_now() {
  local out digest
  out="$(setup_cli plan "${ARGS[@]}" "$@")" || return
  digest="$(digest_of "$out")"
  [ -n "$digest" ] || return 1
  setup_cli apply "${ARGS[@]}" "$@" --digest "$digest" >/dev/null
}
sync_now() {
  local out digest
  out="$(sync_cli plan "${ARGS[@]}")" || return
  digest="$(digest_of "$out")"
  sync_cli apply "${ARGS[@]}" --digest "$digest" >/dev/null
}

# $1 folder: a copy of agent-core an upgrade test may change (same modes), printed.
copy_core() {
  mkdir -p "$1" && cp -Rp "$CORE" "$1/agent-core" && printf '%s' "$1/agent-core"
}

# $1 plugin folder, $2 name, $3 version, $4 stack: a minimal stack plugin for the engine. It ships
# one rule, one settings entry, a CLAUDE.md fragment, a gitignore line, a package script and a hook
# wiring for x-guard.sh; the rest is up to the test.
fake_stack() {
  local dir="$1" name="$2" version="$3" stack="$4"
  mkdir -p "$dir/.claude-plugin" "$dir/hooks" "$dir/templates/$stack/_kit" "$dir/templates/$stack/.claude/rules/$stack"
  printf '{"name": "%s", "version": "%s"}\n' "$name" "$version" >"$dir/.claude-plugin/plugin.json"
  cat >"$dir/templates/$stack/_kit/setup.json" <<EOF
{
  "stack": "$stack",
  "conflictsWith": [],
  "questions": [
    {
      "id": "extra",
      "ask": "Install the extra rule?",
      "why": "A test question.",
      "choices": ["yes", "no"],
      "recommended": "no",
      "install": {"yes": [".claude/rules/$stack/extra.md"]},
      "settings": {"yes": {"/permissions/allow": ["Bash($stack extra:*)"]}}
    }
  ],
  "gitignore": ["$stack-cache/"],
  "packageScripts": {"$stack:check": "echo $stack"}
}
EOF
  printf '### %s rules\n\n- one line from %s\n' "$name" "$name" >"$dir/templates/$stack/_kit/claude-md.md"
  printf 'the %s rule\n' "$stack" >"$dir/templates/$stack/.claude/rules/$stack/main.md"
  printf 'the extra rule\n' >"$dir/templates/$stack/.claude/rules/$stack/extra.md"
  printf '{"permissions": {"allow": ["Bash(%s build:*)", "Bash(%s extra:*)"]}}\n' "$stack" "$stack" \
    >"$dir/templates/$stack/.claude/settings.json"
  cat >"$dir/hooks/hooks.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/x-guard.sh\"", "timeout": 10}]}]}}
EOF
}

# $1 file, $2 python expression over `d` (the parsed JSON): prints the result.
json_q() {
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8")); r = eval(sys.argv[2]); print(r if isinstance(r, str) else json.dumps(r, sort_keys=True))' "$1" "$2"
}

# $1 path: its permission bits in octal, e.g. 600 (portable where stat's flags are not).
mode_of() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }

# $1 file: its SHA-256 as the lock writes it.
sha_of() {
  python3 -c 'import hashlib, sys; print("sha256:" + hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# $1 folder: every path under it (.git aside) with its mode, and a file's hash or a link's target,
# to prove a folder unchanged.
tree_state() {
  python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
for folder, dirs, files in os.walk(root):
    dirs[:] = sorted(d for d in dirs if not (folder == root and d == ".git"))
    for name in sorted(dirs + files):
        path = os.path.join(folder, name)
        st = os.lstat(path)
        rel = os.path.relpath(path, root)
        if os.path.islink(path):
            print(rel, "link", os.readlink(path))
        elif os.path.isfile(path):
            with open(path, "rb") as fh:
                print(rel, oct(st.st_mode & 0o7777), hashlib.sha256(fh.read()).hexdigest())
        else:
            print(rel, oct(st.st_mode & 0o7777), "dir")
PY
}
