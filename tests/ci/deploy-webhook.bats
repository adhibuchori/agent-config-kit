#!/usr/bin/env bats
# actions/deploy-webhook: its trigger script is agent-deploy's, byte for byte, and notify-docs.sh sends
# app-deployed to a docs repository against a local HTTPS stand-in for the GitHub API
# (tests/agent-deploy's mock_server.py). trigger-deploy.sh itself is tested in tests/agent-deploy.

load helpers
load ../agent-deploy/helpers

ACTION="$KIT_ROOT/actions/deploy-webhook"
NOTIFY="$ACTION/scripts/notify-docs.sh"
TOKEN=docs-token-for-tests

setup_file() { mock_start; }
teardown_file() { mock_stop; }

setup() {
  mock_reset
  unset DOCS_REPOSITORY DOCS_DISPATCH_TOKEN
  export GITHUB_API_URL="$MOCK/api"
  mock_routes '{"/api/repos/o/docs/dispatches": {"status": 204, "body": ""}}'
}

notify() { run --separate-stderr "$RUN_BASH" "$NOTIFY"; }

@test "deploy-webhook: the action's trigger script is agent-deploy's trigger-deploy.sh, byte for byte" {
  cmp "$ACTION/scripts/trigger-deploy.sh" "$KIT_ROOT/plugins/agent-deploy/templates/deploy/scripts/deploy/trigger-deploy.sh"
  [ -x "$ACTION/scripts/trigger-deploy.sh" ] && [ -x "$NOTIFY" ]
}

@test "notify-docs: no docs repository sends nothing; one without a token warns and sends nothing" {
  notify
  [ "$status" -eq 0 ]
  [ -z "$output$stderr" ]
  DOCS_REPOSITORY=o/docs notify
  [ "$status" -eq 0 ]
  output="$stderr" assert_has "DOCS_DISPATCH_TOKEN is not set; the docs site was not told about this deploy"
  [ "$(mock_count)" -eq 0 ]
}

@test "notify-docs: it sends app-deployed to the docs repository with the token in a header" {
  DOCS_REPOSITORY=o/docs DOCS_DISPATCH_TOKEN="$TOKEN" notify
  [ "$status" -eq 0 ]
  assert_has "Sent app-deployed to o/docs."
  assert_lacks "$TOKEN"
  mock_requests /api/repos/o/docs/dispatches | python3 -c '
import json, sys
entry = json.loads(sys.stdin.readline())
assert entry["method"] == "POST", entry
assert json.loads(entry["body"]) == {"event_type": "app-deployed"}, entry
assert entry["headers"]["authorization"].startswith("Bearer "), entry
'
}

@test "notify-docs: a refusal fails and says the deploy itself was accepted; a bad repository is a usage error" {
  mock_routes '{"/api/repos/o/docs/dispatches": {"status": 403, "json": {"message": "Resource not accessible"}}}'
  DOCS_REPOSITORY=o/docs DOCS_DISPATCH_TOKEN="$TOKEN" notify
  [ "$status" -eq 1 ]
  output="$stderr" assert_has "GitHub did not accept app-deployed for o/docs (HTTP 403)"
  output="$stderr" assert_has "The deploy itself was accepted."
  output="$output$stderr" assert_lacks "$TOKEN"
  for bad in docs o/docs/x '../x' 'o/d s'; do
    DOCS_REPOSITORY="$bad" DOCS_DISPATCH_TOKEN="$TOKEN" run -2 "$RUN_BASH" "$NOTIFY"
  done
  GITHUB_API_URL=http://127.0.0.1:9/api DOCS_REPOSITORY=o/docs DOCS_DISPATCH_TOKEN="$TOKEN" run -2 "$RUN_BASH" "$NOTIFY"
}
