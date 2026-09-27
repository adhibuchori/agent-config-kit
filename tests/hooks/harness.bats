#!/usr/bin/env bats
# The kit's own probe harness (templates/common/scripts/check/hook-probes.sh, the file setup installs
# into a project) run against the plugin's scripts: every probe of the table, in a linked worktree
# too, each hook's fail modes, the plugin-mode gate, db-guard's SQL reading, and the unlock and .env
# helpers run as the user runs them. It takes a few minutes; `bats --filter-tags '!slow'` skips it.

load ../helpers/common

# bats test_tags=slow
@test "hook-probes.sh passes against plugins/agent-core/scripts with no failure" {
  run --separate-stderr env HOOKS_DIR="$HOOKS" "$HOOK_BASH" "$COMMON/scripts/check/hook-probes.sh"
  if [ "$status" -ne 0 ]; then
    grep -E 'FAIL|error' <<<"$output" >&2
    return 1
  fi
  [[ "$output" =~ hook\ probes:\ ([0-9]+)\ passed,\ 0\ failed ]]
  [ "${BASH_REMATCH[1]}" -ge 1500 ]
}
