#!/usr/bin/env bats
# The optional CI callers each plugin's setup offers: the DeepSeek review (every stack), React Doctor
# (fe-nextjs-static), deploy on merge and the AI-config strip (agent-deploy), and the CODEOWNERS
# starter. Each is installed only when its question says yes; a caller that still pins the kit's
# reusable workflow to the release placeholder is held back (warned, listed as held by sync --check,
# never written), and one pinned to a real commit is created. Every test builds its own repo.

load ../helpers/common

PLUGINS="$KIT_ROOT/plugins"
ZERO='@0000000000000000000000000000000000000000'

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
}

cli() { # tool plugin stack args...
  local tool="$1" plugin="$2" stack="$3"
  shift 3
  "$CORE/bin/$tool" "$@" --templates "$PLUGINS/$plugin/templates" --stack "$stack" --project "$P"
}

apply_answers() { # plugin stack answers...
  local plugin="$1" stack="$2" digest
  shift 2
  digest="$(cli agent-setup "$plugin" "$stack" plan "$@" --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  cli agent-setup "$plugin" "$stack" apply "$@" --digest "$digest" >/dev/null
}

# expect_caller plugin stack question dest: no leaves it out; yes holds it while the template pins the
# placeholder and creates it once the template pins a commit.
expect_caller() {
  local plugin="$1" stack="$2" q="$3" dest="$4" tpl
  tpl="$PLUGINS/$plugin/templates/$stack/$dest"
  [ -f "$tpl" ]
  run -0 --separate-stderr cli agent-setup "$plugin" "$stack" plan --answer "$q=no"
  [[ "$output" != *"$dest"* ]] || {
    echo "$q=no still plans $dest" >&2
    return 1
  }
  run -0 --separate-stderr cli agent-setup "$plugin" "$stack" plan --answer "$q=yes"
  if grep -qF "$ZERO" "$tpl"; then
    grep -qE "^  warn +${dest//./\\.} +not installed: .*release placeholder" <<<"$output" || {
      echo "$dest is not held back: $output" >&2
      return 1
    }
    [[ "$output" != *"  create   $dest"* ]] || false
  else
    grep -qE "^  create +${dest//./\\.}( |$)" <<<"$output" || {
      echo "$dest is not created: $output" >&2
      return 1
    }
  fi
}

@test "ci-callers: every stack offers the DeepSeek review behind deepseek-review, recommended no" {
  local pair plugin stack
  for pair in agent-fe-nextjs:fe-nextjs agent-fe-nextjs-static:fe-nextjs-static agent-be-hono:be-hono \
    agent-ai-fastapi:ai-fastapi agent-docs-nextra:docs-nextra; do
    plugin="${pair%%:*}" stack="${pair#*:}"
    expect_caller "$plugin" "$stack" deepseek-review .github/workflows/deepseek-review.yml
    run -0 --separate-stderr cli agent-setup "$plugin" "$stack" questions --json
    python3 -c '
import json, sys
q = [q for q in json.loads(sys.argv[1])["questions"] if q["id"] == "deepseek-review"]
assert len(q) == 1 and q[0]["recommended"] == "no" and "DEEPSEEK_API_KEY" in q[0]["why"], q' "$output"
  done
}

@test "ci-callers: agent-deploy offers deploy on merge and the strip, each behind its own question" {
  expect_caller agent-deploy deploy deploy-on-merge .github/workflows/deploy.yml
  expect_caller agent-deploy deploy strip-ai .github/workflows/strip-ai.yml
}

@test "ci-callers: a held caller is not written, not locked, and sync --check lists it as held" {
  local tpl="$PLUGINS/agent-deploy/templates/deploy/.github/workflows/deploy.yml"
  grep -qF "$ZERO" "$tpl" || skip "the deploy caller is pinned to a release commit"
  apply_answers agent-deploy deploy --answer deploy-on-merge=yes
  [ ! -e "$P/.github/workflows/deploy.yml" ]
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert ".github/workflows/deploy.yml" not in d["plugins"]["agent-deploy"]["files"]' \
    "$P/.claude/agent-config-kit.lock"
  run cli agent-sync agent-deploy deploy check
  [[ "$output" == *"held  .github/workflows/deploy.yml"* ]] || false
}

@test "ci-callers: a pinned caller is created by setup and matches the template byte for byte" {
  local tpl="$PLUGINS/agent-be-hono/templates/be-hono/.github/workflows/deepseek-review.yml"
  grep -qF "$ZERO" "$tpl" && skip "the review caller still holds the release placeholder"
  apply_answers agent-be-hono be-hono --answer deepseek-review=yes
  cmp "$P/.github/workflows/deepseek-review.yml" "$tpl"
  run -0 cli agent-sync agent-be-hono be-hono check
}

@test "ci-callers: fe-nextjs-static's React Doctor installs the workflow and its config together, or neither" {
  local plugin=agent-fe-nextjs-static stack=fe-nextjs-static
  run -0 --separate-stderr cli agent-setup "$plugin" "$stack" plan --answer react-doctor=yes
  [[ "$output" == *"  create   .github/workflows/react-doctor.yml"* ]] || false
  [[ "$output" == *"  create   doctor.config.json"* ]] || false
  run -0 --separate-stderr cli agent-setup "$plugin" "$stack" plan --answer react-doctor=no
  [[ "$output" != *"react-doctor.yml"* && "$output" != *"doctor.config.json"* ]] || false
}

@test "ci-callers: every stack seeds a CODEOWNERS starter: created once, then the project's own" {
  local pair plugin stack
  for pair in agent-fe-nextjs:fe-nextjs agent-fe-nextjs-static:fe-nextjs-static agent-be-hono:be-hono \
    agent-ai-fastapi:ai-fastapi agent-docs-nextra:docs-nextra; do
    plugin="${pair%%:*}" stack="${pair#*:}"
    run -0 --separate-stderr cli agent-setup "$plugin" "$stack" plan
    [[ "$output" == *"  seed     .github/CODEOWNERS"* ]] || {
      echo "$plugin does not seed .github/CODEOWNERS" >&2
      return 1
    }
    grep -q '^\*  *@your-github-handle$' "$PLUGINS/$plugin/templates/$stack/.github/CODEOWNERS"
    grep -q '^/\.github/  *@your-github-handle$' "$PLUGINS/$plugin/templates/$stack/.github/CODEOWNERS"
  done
}
