#!/usr/bin/env bats
# conflictsWith across every stack plugin: a primary stack (one that names any conflict) names every
# other primary stack, and the lists are mutual. The lists are derived from the plugins on disk, so a
# new stack plugin needs no test edit here; one that forgets a partner fails until both name it.

load ../helpers/common

KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"

conflicts() {
  python3 - "$KIT_ROOT" <<'PY'
import glob, json, os, sys

root = sys.argv[1]
lists = {}
for f in sorted(glob.glob(os.path.join(root, "plugins/*/templates/*/_kit/setup.json"))):
    plugin = f[len(root) + 1:].split("/")[1]
    lists[plugin] = json.load(open(f)).get("conflictsWith") or []
primary = sorted(p for p, names in lists.items() if names)
problems = []
for p in primary:
    want = [q for q in primary if q != p]
    if sorted(lists[p]) != want:
        problems.append(f"{p}: conflictsWith is {sorted(lists[p])}, expected every other primary stack {want}")
    if lists[p] != sorted(lists[p]):
        problems.append(f"{p}: conflictsWith is not sorted")
for p, names in lists.items():
    for q in names:
        if q not in lists:
            problems.append(f"{p}: names {q}, which is no stack plugin")
        elif p not in lists[q]:
            problems.append(f"{p} names {q}, but {q} does not name {p}")
print("\n".join(problems) or f"{len(primary)} primary stacks, every pair mutual")
sys.exit(1 if problems else 0)
PY
}

@test "conflicts: every primary stack names every other one, and the lists are mutual" {
  run conflicts
  [ "$status" -eq 0 ]
  [[ "$output" == *"primary stacks, every pair mutual"* ]]
}

@test "conflicts: a stack that drops a partner fails, naming both" {
  local copy="$BATS_TEST_TMPDIR/kit"
  mkdir -p "$copy"
  cp -R "$KIT_ROOT/plugins" "$copy/"
  local f="$copy/plugins/agent-be-hono/templates/be-hono/_kit/setup.json"
  python3 - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["conflictsWith"].remove("agent-fe-nextjs")
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
  KIT_ROOT="$copy" run conflicts
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-fe-nextjs names agent-be-hono, but agent-be-hono does not name agent-fe-nextjs"* ]]
}
