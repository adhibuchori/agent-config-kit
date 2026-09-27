# shellcheck shell=bash
# Shared by tests/ci/*.bats: the tests for this repository's own CI pieces (actions/, scripts/).
# Every test builds its fixtures in its own $BATS_TEST_TMPDIR, with an isolated git identity, and
# no test needs the network: toolchains the gate would install are stubs on PATH.
bats_require_minimum_version 1.5.0

KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
QG="$KIT_ROOT/actions/quality-gate/scripts"
STRIP="$KIT_ROOT/actions/strip-ai/scripts"
export KIT_ROOT QG STRIP

ci_isolate() {
  unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GITHUB_ACTIONS GITHUB_OUTPUT GITHUB_PATH
  unset CI QG_STACK QG_BASE QG_BASE_REF QG_PM QG_PACKAGE_MANAGER QG_COVERAGE_THRESHOLD QG_ENV_FILE
  unset QG_STRICT QG_IGNORE_SCRIPTS QG_INTEGRATION_TESTS RUNNER_TEMP
  mkdir -p "$BATS_TEST_TMPDIR/home"
  cat >"$BATS_TEST_TMPDIR/home/gitconfig" <<'EOF'
[user]
	email = ci-test@example.invalid
	name = ci-test
[commit]
	gpgsign = false
[init]
	defaultBranch = main
EOF
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/home/gitconfig" GIT_CONFIG_NOSYSTEM=1
}

need_node() {
  command -v node >/dev/null 2>&1 || skip "node is not installed"
}

# Puts executable stubs first on PATH. Each logs its argv to $STUB_LOG and exits with the value of
# STUB_<NAME>_EXIT (default 0). Only the tools the gate would install are stubbed; git, node and the
# coreutils stay real.
stub_tools() {
  STUBS="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$STUBS"
  : >"$STUB_LOG"
  local t var
  for t in "$@"; do
    var="STUB_$(printf '%s' "$t" | tr '[:lower:]-' '[:upper:]_')_EXIT"
    cat >"$STUBS/$t" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$t" "\$*" >>"$STUB_LOG"
exit "\${$var:-0}"
EOF
    chmod +x "$STUBS/$t"
  done
  export STUBS STUB_LOG
  PATH="$STUBS:$PATH"
}

# A PATH that holds only the basic tools and the stubs: for proving a tool is absent.
path_without() { # $@ commands that must not be found
  local keep="$BATS_TEST_TMPDIR/pathkeep" c src
  mkdir -p "$keep"
  for c in bash sh env git node cat grep sed awk tr cut head tail wc sort mktemp rm mkdir cp mv \
    find od dirname basename date printf tee ls chmod uname xargs readlink; do
    src=$(command -v "$c" 2>/dev/null) || continue
    case " $* " in *" $c "*) continue ;; esac
    ln -sf "$src" "$keep/$c"
  done
  printf '%s' "${STUBS:+$STUBS:}$keep"
}

# A toy repository on branch `feature`, one commit ahead of a base that the gate sees as origin/dev
# (a remote-tracking ref, as a pull-request checkout has).
toy_repo() { # $1 dir
  mkdir -p "$1"
  git init -q -b dev "$1"
  (
    cd "$1" || exit 1
    printf '{\n  "name": "toy",\n  "private": true,\n  "scripts": { "build": "next build" }\n}\n' >package.json
    printf '{"lockfileVersion": 3}\n' >package-lock.json
    mkdir -p scripts/check src
    printf 'code\techo gate\n' >scripts/check/gates.list
    # The repo's gates: record the run and write the coverage report the floor reads.
    cat >scripts/check/gates.sh <<'EOF'
#!/usr/bin/env bash
echo "gates.sh ran (GATES_PM=${GATES_PM:-})"
if [ -n "${TOY_LCOV:-}" ]; then
  mkdir -p coverage
  printf '%b' "$TOY_LCOV" >coverage/lcov.info
fi
exit "${TOY_GATES_EXIT:-0}"
EOF
    printf 'export const page = () => "home";\n' >src/page.ts
    git add -A
    git commit -q -m base
    git update-ref refs/remotes/origin/dev HEAD
    git checkout -q -b feature
  )
}

# Commits every change in the toy repo on its feature branch.
toy_commit() { # $1 dir, $2 message
  git -C "$1" add -A && git -C "$1" commit -q -m "${2:-change}"
}

# An lcov report with one file: $1 lines found, $2 lines hit, $3 functions found, $4 functions hit.
lcov() {
  printf 'SF:src/page.ts\\nFNF:%s\\nFNH:%s\\nLF:%s\\nLH:%s\\nend_of_record\\n' "$3" "$4" "$1" "$2"
}
