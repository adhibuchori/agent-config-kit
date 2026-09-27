#!/usr/bin/env bats
# scripts/workflow-policy.py: triggers, merge guards, permissions, secrets, checkout credentials, the
# pins of calls to this repository's reusable workflows, and Dependabot. It needs PyYAML: through uv
# at the pinned release CI uses, or a python3 that already has it.

load helpers

SHA=0123456789abcdef0123456789abcdef01234567
ZERO=0000000000000000000000000000000000000000

setup() {
  ci_isolate
  if command -v uv >/dev/null 2>&1; then
    PY=(uv run --quiet --no-project --with pyyaml==6.0.3 python3)
  elif python3 -c 'import yaml' 2>/dev/null; then
    PY=(python3)
  else
    skip "neither uv nor a python3 with PyYAML is available"
  fi
  K="$BATS_TEST_TMPDIR/kit"
  T="$K/plugins/agent-demo/templates/demo/.github/workflows"
  mkdir -p "$K/.github/workflows" "$T"
  cat >"$K/.github/workflows/demo-quality-gate.yml" <<'EOF'
name: gate
on:
  workflow_call:
permissions:
  contents: read
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
EOF
  caller "$SHA"
}

caller() { # $1 sha, $2 comment (default "# v1.0.0")
  cat >"$T/quality-gate.yml" <<EOF
on:
  pull_request:
permissions:
  contents: read
jobs:
  quality-gate:
    permissions:
      contents: read
    uses: adhibuchori/agent-config-kit/.github/workflows/demo-quality-gate.yml@$1 ${2-# v1.0.0}
EOF
}

policy() { run --separate-stderr "${PY[@]}" "$KIT_ROOT/scripts/workflow-policy.py" "$@" "$K"; }

@test "workflow-policy: a compliant repository and template pass" {
  policy
  [ "$status" -eq 0 ]
  [[ "$output" == *"scanned 2 workflow file(s)"* ]]
  [[ "$output" == *"0 problem(s), 0 warning(s)"* ]]
}

@test "workflow-policy: push, schedule, pull_request_target and workflow_dispatch are refused" {
  printf 'on:\n  push:\n  schedule:\n    - cron: "0 0 * * 1"\n  pull_request_target:\n  workflow_dispatch:\npermissions: {}\njobs: {}\n' \
    >"$K/.github/workflows/bad.yml"
  policy
  [ "$status" -eq 1 ]
  for t in push schedule pull_request_target workflow_dispatch; do
    [[ "$output" == *"trigger \`$t\` is not allowed"* ]]
  done
}

@test "workflow-policy: issue_comment and repository_dispatch are refused outside their exceptions" {
  printf 'on:\n  issue_comment:\n  repository_dispatch:\npermissions: {}\njobs: {}\n' >"$K/.github/workflows/chatops.yml"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"chatops.yml: trigger \`issue_comment\` is not allowed"* ]]
  [[ "$output" == *"chatops.yml: trigger \`repository_dispatch\` is not allowed"* ]]
}

@test "workflow-policy: the docs-nextra changelog alone may also take repository_dispatch" {
  local d="$K/plugins/agent-docs-nextra/templates/docs-nextra/.github/workflows"
  mkdir -p "$d"
  printf 'on:\n  pull_request:\n    types: [closed]\n  repository_dispatch:\npermissions:\n  contents: read\njobs:\n  gen:\n    if: github.event_name == %s || github.event.pull_request.merged == true\n    runs-on: ubuntu-latest\n    steps: []\n' \
    "'repository_dispatch'" >"$d/changelog.yaml"
  policy
  [ "$status" -eq 0 ]
  cp "$d/changelog.yaml" "$d/other.yaml"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"other.yaml: trigger \`repository_dispatch\` is not allowed"* ]]
  [[ "$output" != *"changelog.yaml: trigger"* ]]
}

# A template's DeepSeek review caller, and the reusable workflow it calls: the one shape in which
# issue_comment is allowed. $1 names the caller file (default: deepseek-review.yml).
comment_caller() {
  cat >"$K/.github/workflows/deepseek-review.yml" <<'EOF'
on:
  workflow_call:
permissions:
  contents: read
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: $/actions/deepseek-review
EOF
  cat >"$T/${1:-deepseek-review.yml}" <<EOF
on:
  pull_request:
    types: [opened]
  issue_comment:
    types: [created]
permissions:
  contents: read
jobs:
  deepseek-review:
    if: >-
      (github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository) ||
      (github.event_name == 'issue_comment' && github.event.issue.pull_request &&
      startsWith(github.event.comment.body, '/ask-deepseek') &&
      contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association))
    permissions:
      contents: read
      pull-requests: write
    uses: adhibuchori/agent-config-kit/.github/workflows/deepseek-review.yml@$SHA # v1.0.0
EOF
}

# replace_in FILE OLD NEW: a literal replacement, the same with BSD and GNU tools.
replace_in() {
  python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b))' "$@"
}

@test "workflow-policy: a template's deepseek-review.yml may take issue_comment in the safe shape, no other file may" {
  comment_caller
  policy
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 problem(s)"* ]]
  comment_caller other.yml
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"other.yml: trigger \`issue_comment\` is not allowed"* ]]
  [[ "$output" != *"deepseek-review.yml: trigger"* ]]
}

@test "workflow-policy: the comment trigger fails without the trust guard, with more types, or with a wider token" {
  local f="$T/deepseek-review.yml"
  comment_caller
  replace_in "$f" '"COLLABORATOR"]' '"COLLABORATOR","CONTRIBUTOR"]'
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"job \`deepseek-review\` must run on a comment only for a pull request and an OWNER, MEMBER or COLLABORATOR (also allows CONTRIBUTOR)"* ]]
  comment_caller
  replace_in "$f" "'issue_comment' && github.event.issue.pull_request &&" "'issue_comment' &&"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"(missing github.event.issue.pull_request)"* ]]
  comment_caller
  replace_in "$f" 'types: [created]' 'types: [created, edited]'
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"issue_comment must be limited to \`types: [created]\`"* ]]
  comment_caller
  replace_in "$f" '      pull-requests: write' $'      pull-requests: write\n      issues: write'
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"job \`deepseek-review\` may hold \`contents: read\` and \`pull-requests: write\` only"* ]]
  comment_caller
  replace_in "$f" $'permissions:\n  contents: read\njobs:' $'permissions:\n  contents: write\njobs:'
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs top-level \`permissions: contents: read\` and nothing more"* ]]
}

@test "workflow-policy: a comment-triggered job only calls the review, and the review never checks out" {
  comment_caller
  replace_in "$T/deepseek-review.yml" 'workflows/deepseek-review.yml@' 'workflows/demo-quality-gate.yml@'
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"job \`deepseek-review\` must be a call to this repository's deepseek-review.yml and nothing else"* ]]
  comment_caller
  printf '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with:\n          persist-credentials: false\n' \
    >>"$K/.github/workflows/deepseek-review.yml"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *".github/workflows/deepseek-review.yml: job \`review\` checks out code"* ]]
}

@test "workflow-policy: a closed pull request job needs a merge guard, directly or through needs" {
  cat >"$K/.github/workflows/deploy.yml" <<'EOF'
on:
  pull_request:
    types: [closed]
permissions:
  contents: read
jobs:
  build:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps: []
  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps: []
  notify:
    runs-on: ubuntu-latest
    steps: []
EOF
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"job \`notify\` can run on a closed pull request that was not merged"* ]]
  [[ "$output" != *"job \`deploy\`"* ]]
}

@test "workflow-policy: no top-level permissions, secrets: inherit, and an implicit persist-credentials fail" {
  cat >"$K/.github/workflows/loose.yml" <<'EOF'
on: pull_request
jobs:
  call:
    uses: ./.github/workflows/demo-quality-gate.yml
    secrets: inherit
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
EOF
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"loose.yml: no top-level \`permissions:\`"* ]]
  [[ "$output" == *"job \`call\` uses \`secrets: inherit\`"* ]]
  [[ "$output" == *"job \`build\` step 1 checks out without an explicit \`persist-credentials:\`"* ]]
}

@test "workflow-policy: the placeholder pin warns, and fails with --release" {
  caller "$ZERO"
  policy
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN:"*"placeholder SHA"* ]]
  policy --release
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL:"*"placeholder SHA"* ]]
}

@test "workflow-policy: --release checks the pin is a commit here and matches its tag" {
  git -C "$K" init -q -b main && git -C "$K" add -A && git -C "$K" commit -q -m one
  policy --release
  [ "$status" -eq 1 ]
  [[ "$output" == *"$SHA is not a commit in this clone"* ]]
  local head
  head=$(git -C "$K" rev-parse HEAD)
  caller "$head"
  git -C "$K" commit -qam two
  git -C "$K" tag v1.0.0 "$head"
  policy --release
  [ "$status" -eq 0 ]
  git -C "$K" tag -f v1.0.0 HEAD >/dev/null
  policy --release
  [ "$status" -eq 1 ]
  [[ "$output" == *"tag v1.0.0 is"*"not $head"* ]]
}

@test "workflow-policy: a short SHA, no release comment, or a workflow this repo lacks fails" {
  caller 0123456
  policy
  [[ "$output" == *"pin \`0123456\` is not a full 40-hex commit SHA"* ]]
  caller "$SHA" ""
  policy
  [[ "$output" == *"needs an exact \`# vX.Y.Z\` release comment"* ]]
  sed -i.bak 's/demo-quality-gate/ghost-quality-gate/' "$T/quality-gate.yml"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"calls .github/workflows/ghost-quality-gate.yml, which this repository does not have"* ]]
}

@test "workflow-policy: a Dependabot config, here or in a template, fails" {
  printf 'version: 2\n' >"$K/.github/dependabot.yml"
  printf 'version: 2\n' >"$T/../dependabot.yml"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *".github/dependabot.yml: Dependabot config is not used"* ]]
  [[ "$output" == *"templates/demo/.github/dependabot.yml: Dependabot config"* ]]
}

@test "workflow-policy: no workflow files is a failure, not a pass" {
  rm -rf "$K/.github" "$K/plugins"
  policy
  [ "$status" -eq 1 ]
  [[ "$output" == *"scanned 0 workflow file(s)"* ]]
}
