#!/usr/bin/env bats
# scripts/version-sync.mjs on a small git repo: versions, marketplace, dependencies, CHANGELOG.md,
# the caller pins' release comments, tags, and the bump rules against a base commit.

load helpers

SHA=0123456789abcdef0123456789abcdef01234567

setup() {
  ci_isolate
  need_node
  K="$BATS_TEST_TMPDIR/kit"
  mkdir -p "$K/.claude-plugin" "$K/plugins/agent-core/.claude-plugin" "$K/plugins/agent-demo/.claude-plugin" \
    "$K/plugins/agent-demo/templates/demo/.github/workflows" "$K/.github/workflows" "$K/actions/quality-gate"
  cat >"$K/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "agent-config-kit",
  "plugins": [
    { "name": "agent-core", "source": "./plugins/agent-core", "description": "Core." },
    { "name": "agent-demo", "source": "./plugins/agent-demo", "description": "Demo." }
  ]
}
EOF
  manifest agent-core 1.0.0 Core.
  manifest agent-demo 1.0.0 Demo. '"dependencies": ["agent-core"], '
  printf 'jobs:\n  gate:\n    uses: adhibuchori/agent-config-kit/.github/workflows/demo-quality-gate.yml@%s # v1.0.0\n' "$SHA" \
    >"$K/plugins/agent-demo/templates/demo/.github/workflows/quality-gate.yml"
  printf 'name: gate\n' >"$K/.github/workflows/demo-quality-gate.yml"
  printf 'runs: {}\n' >"$K/actions/quality-gate/action.yml"
  changelog '1.0.0' '1.0.0'
  git -C "$K" init -q -b main && git -C "$K" add -A && git -C "$K" commit -q -m base
}

manifest() { # name version description [extra json]
  printf '{ "name": "%s", "version": "%s", %s"description": "%s" }\n' "$1" "$2" "${4:-}" "$3" \
    >"$K/plugins/$1/.claude-plugin/plugin.json"
}

changelog() { # core version, demo version
  cat >"$K/CHANGELOG.md" <<EOF
# Changelog

## [Unreleased]

## [1.0.0] - 2026-09-26

### agent-core $1

#### Added

- The guards.

### agent-demo $2

#### Added

- The demo rules.
EOF
}

sync() { run --separate-stderr node "$KIT_ROOT/scripts/version-sync.mjs" --root "$K" "$@"; }

@test "version-sync: a consistent repo passes --check" {
  sync --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-core 1.0.0, agent-demo 1.0.0; in sync"* ]]
}

@test "version-sync: a version that is not X.Y.Z, and a version in the marketplace, fail" {
  manifest agent-core 1.0 Core.
  sed -i.bak 's|"source": "./plugins/agent-demo",|"source": "./plugins/agent-demo", "version": "1.0.0",|' "$K/.claude-plugin/marketplace.json"
  sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'agent-core/.claude-plugin/plugin.json: version "1.0" is not X.Y.Z'* ]]
  [[ "$output" == *"agent-demo carries a version"* ]]
}

@test "version-sync: a plugin that does not depend on agent-core fails" {
  manifest agent-demo 1.0.0 Demo.
  sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'agent-demo/.claude-plugin/plugin.json: dependencies must include "agent-core"'* ]]
}

@test "version-sync: without --check it copies the description into the marketplace" {
  manifest agent-core 1.0.0 'Core, reworded.'
  sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-core description differs from plugin.json"* ]]
  sync
  [ "$status" -eq 0 ]
  grep -qF '"description": "Core, reworded."' "$K/.claude-plugin/marketplace.json"
  sync --check
  [ "$status" -eq 0 ]
}

@test "version-sync: the changelog needs Unreleased first, real dates, newest first, and every current version" {
  manifest agent-demo 1.1.0 Demo. '"dependencies": ["agent-core"], '
  sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'no "### agent-demo 1.1.0" heading'* ]]
  changelog 1.0.0 1.0.0
  printf '\n## [0.9.0] - 2026-02-30\n\n## [1.1.0] - 2026-09-27\n' >>"$K/CHANGELOG.md"
  sync --check
  [[ "$output" == *"2026-02-30 is not a real date"* ]]
  [[ "$output" == *"releases must be newest first"* ]]
  printf '# Changelog\n\n## [1.0.0] - 2026-09-26\n\n## [Unreleased]\n' >"$K/CHANGELOG.md"
  sync --check
  [[ "$output" == *'the first "## " heading must be "## [Unreleased]"'* ]]
  rm "$K/CHANGELOG.md"
  sync --check
  [[ "$output" == *"CHANGELOG.md: missing"* ]]
}

@test "version-sync: a caller that pins a release the changelog does not have fails" {
  sed -i.bak 's/# v1.0.0/# v1.2.0/' "$K/plugins/agent-demo/templates/demo/.github/workflows/quality-gate.yml"
  sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"pins # v1.2.0, which is not a release in CHANGELOG.md"* ]]
}

@test "version-sync: a plugin tag newer than plugin.json fails" {
  git -C "$K" tag agent-demo--v1.0.0
  sync --check
  [ "$status" -eq 0 ]
  git -C "$K" tag agent-demo--v1.1.0
  sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"tag agent-demo--v1.1.0 is newer than plugin.json's 1.0.0"* ]]
}

@test "version-sync --base: a changed plugin needs a higher version and a changelog entry" {
  printf 'new rule\n' >"$K/plugins/agent-demo/rule.md"
  git -C "$K" add -A && git -C "$K" commit -q -m change
  sync --check --base HEAD~1
  [ "$status" -eq 1 ]
  [[ "$output" == *"plugins/agent-demo: 1 file(s) changed since HEAD~1 but the version is still 1.0.0"* ]]
  [[ "$output" == *"the changelog did not"* ]]
  manifest agent-demo 1.0.1 Demo. '"dependencies": ["agent-core"], '
  changelog 1.0.0 1.0.1
  git -C "$K" add -A && git -C "$K" commit -q -m bump
  sync --check --base HEAD~2
  [ "$status" -eq 0 ]
}

@test "version-sync --base: an action or reusable workflow change needs a changelog entry" {
  printf 'runs: { using: composite }\n' >"$K/actions/quality-gate/action.yml"
  git -C "$K" add -A && git -C "$K" commit -q -m action
  sync --check --base HEAD~1
  [ "$status" -eq 1 ]
  [[ "$output" == *"a plugin, an action or a reusable workflow changed"* ]]
}

@test "version-sync --base: an unknown base exits 2; a bad argument exits 2" {
  sync --check --base nope
  [ "$status" -eq 2 ]
  sync --check --base --root
  [ "$status" -eq 2 ]
  sync --frobnicate
  [ "$status" -eq 2 ]
}
