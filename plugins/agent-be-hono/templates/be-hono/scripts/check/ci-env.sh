#!/usr/bin/env bash
# Runs a command with the environment CI's unit tests get, and nothing else: PATH, HOME, TMPDIR, the
# locale, CI=true and CI's test variables. No variable exported in your shell and no .env file
# reaches the command, so a test that quietly reaches a real service with your local credentials
# fails here as it does in CI. scripts/check/gates.list runs the unit tests through it.
#
#   bash scripts/check/ci-env.sh bun run test:coverage
#
# CI's test variables, found through .github/workflows/quality-gate.yml (or .yaml):
#   - a caller of agent-config-kit's be-hono-quality-gate: the committed file it passes as
#     `env-file:` (default .env.ci.example), read as the gate reads it: KEY=VALUE lines, # comments,
#     one layer of quotes, no expansion, and the same names refused;
#   - a workflow that runs the tests itself: its env: blocks, the job's over the workflow's;
#   - no workflow at all: .env.ci.example.
# Bun reads .env, .env.test and .env.local by itself; BUN_OPTIONS=--no-env-file stops every bun
# process the command starts from doing so (CI has none of those files). Fails, rather than running
# with a guess, when that source is missing or unreadable. Exit 2 without a command.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2

[ $# -gt 0 ] || {
  echo "usage: bash scripts/check/ci-env.sh <command...>" >&2
  exit 2
}
if ! command -v python3 >/dev/null 2>&1; then
  echo "::error::ci-env.sh needs python3 to read CI's test variables" >&2
  exit 1
fi

read -r -d '' PARSE <<'PY' || true
import os, re, sys

REFUSED = re.compile(r"^(PATH|HOME|SHELL|ENV|BASH_ENV|IFS|CDPATH|PS4|TMPDIR|CI|LD_.*|DYLD_.*|NODE_OPTIONS|"
                     r"NODE_PATH|PYTHON.*|GITHUB_.*|RUNNER_.*|ACTIONS_.*|GIT_.*|BUN_.*|NPM_CONFIG_.*|UV_.*|QG_.*)$")


def fail(msg):
    print("::error::" + msg, file=sys.stderr)
    sys.exit(1)


def unquote(value):
    if len(value) > 1 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


workflow = next((w for w in (".github/workflows/quality-gate.yml", ".github/workflows/quality-gate.yaml")
                 if os.path.isfile(w)), "")
lines = open(workflow, encoding="utf-8").read().splitlines() if workflow else []


def env_block(indent):
    """KEY=VALUE for the first `env:` block at this indent (0: the workflow's, 4: a job's)."""
    found, inside = [], False
    for line in lines:
        if not inside and re.match("^" + " " * indent + r"env:\s*(#.*)?$", line):
            inside = True
            continue
        if inside:
            m = re.match("^" + " " * (indent + 2) + r"([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", line)
            if m:
                value = unquote(m.group(2))
                if "${{" in value:
                    fail(f"{workflow}: {m.group(1)} is computed by CI, so it cannot be reproduced here")
                found.append(f"{m.group(1)}={value}")
            elif line.strip() and not line.lstrip().startswith("#"):
                break
    return found


if any(re.match(r"^\s*uses:\s*\S*be-hono-quality-gate\.ya?ml@", line) for line in lines) or not workflow:
    # A caller of the reusable gate (whose own env does not reach the called workflow), or no CI
    # workflow here: the committed env file.
    env_file = ".env.ci.example"
    for line in lines:
        m = re.match(r"^\s*env-file:\s*(.*?)\s*(#.*)?$", line)
        if m:
            env_file = unquote(m.group(1))
            break
    where = f"{workflow} passes it to the quality gate" if workflow else "no CI workflow here, so the kit's default"
    if not env_file.endswith(".example"):
        fail(f"env-file must be a committed *.example file of dummy values, got {env_file} ({where})")
    if not os.path.isfile(env_file):
        fail(f"{env_file} is missing ({where}). Commit it with the dummy KEY=VALUE variables the tests "
             "need (comments alone when they need none)")
    for raw in open(env_file, encoding="utf-8").read().splitlines():
        line = raw.rstrip("\r")
        if line == "" or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        key, eq, value = line.partition("=")
        if not eq or not re.match(r"^[A-Z_][A-Z0-9_]*$", key):
            fail(f"{env_file}: a line is not KEY=VALUE with an upper-case KEY")
        if REFUSED.match(key):
            fail(f"{env_file}: {key} changes how the runner or a toolchain behaves; the gate refuses it")
        print(f"{key}={unquote(value)}")
else:
    # A workflow that runs the tests itself: its env blocks, the job's over the workflow's.
    found = env_block(0) + env_block(4)
    if not found:
        fail(f"{workflow} neither calls agent-config-kit's be-hono-quality-gate nor sets an env: block, so "
             "the variables CI's tests run with are unknown")
    print("\n".join(found))
PY

out="$(python3 -c "$PARSE")" || exit 1
vars=()
while IFS= read -r kv; do
  [ -n "$kv" ] && vars+=("$kv")
done <<<"$out"
exec env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" LANG="${LANG:-C.UTF-8}" CI=true \
  BUN_OPTIONS=--no-env-file ${vars[@]+"${vars[@]}"} "$@"
