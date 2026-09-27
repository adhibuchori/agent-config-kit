#!/usr/bin/env bats
# trigger-deploy.sh against a local HTTPS stand-in for a deploy webhook.

load helpers

setup_file() { mock_start; }
teardown_file() { mock_stop; }

SECRET=hook-secret-8b41c

setup() {
  mock_reset
  mock_routes '{}'
  export DEPLOY_WEBHOOK_URL="$MOCK/deploy/$SECRET"
  export DEPLOY_RETRY_DELAYS="0 0"
  # The ref every test deploys unless it says otherwise; the script itself has no default.
  export DEPLOY_REF=refs/heads/main
}

hook() { mock_routes "{\"/deploy/$SECRET\": $1}"; }

@test "a missing webhook URL is a configuration error, not a silent skip" {
  unset DEPLOY_WEBHOOK_URL
  run -2 --separate-stderr "$RUN_BASH" "$TRIGGER"
  output="$stderr" assert_has "DEPLOY_WEBHOOK_URL is not set; refusing to skip the deploy silently."
  [ "$(mock_count)" -eq 0 ]
}

@test "no ref, neither an argument nor DEPLOY_REF, is a usage error before any request" {
  unset DEPLOY_REF
  run -2 --separate-stderr "$RUN_BASH" "$TRIGGER"
  output="$stderr" assert_has "name the ref to deploy: trigger-deploy.sh refs/heads/<branch> (or set DEPLOY_REF)"
  [ "$(mock_count)" -eq 0 ]
}

@test "a plain-http or malformed webhook URL is refused before any request" {
  DEPLOY_WEBHOOK_URL="http://127.0.0.1:9/deploy/$SECRET" run -2 "$RUN_BASH" "$TRIGGER"
  DEPLOY_WEBHOOK_URL="$MOCK/deploy/a b" run -2 "$RUN_BASH" "$TRIGGER"
  DEPLOY_WEBHOOK_URL="$MOCK/deploy/a\"b" run -2 "$RUN_BASH" "$TRIGGER"
  [ "$(mock_count)" -eq 0 ]
}

@test "a ref that is not refs/heads or refs/tags, or carries odd characters, is refused" {
  for ref in main refs/pull/1/head 'refs/heads/ma"in' 'refs/heads/a..b' 'refs/heads/' 'refs/heads/x y'; do
    run -2 "$RUN_BASH" "$TRIGGER" "$ref"
  done
  [ "$(mock_count)" -eq 0 ]
}

@test "a 200 is accepted, with a push-shaped payload for the ref in DEPLOY_REF" {
  hook '{"status": 200, "body": "queued"}'
  run -0 "$RUN_BASH" "$TRIGGER"
  assert_has "attempt 1/3: HTTP 200 queued"
  assert_has "accepted the deploy of refs/heads/main. Accepted is not deployed"
  [ "$(mock_count)" -eq 1 ]
  mock_requests "/deploy/$SECRET" | python3 -c '
import json, sys
entry = json.loads(sys.stdin.readline())
assert entry["method"] == "POST", entry
assert json.loads(entry["body"]) == {"ref": "refs/heads/main", "commits": []}, entry
assert entry["headers"]["x-github-event"] == "push", entry
assert entry["headers"]["content-type"] == "application/json", entry
'
}

@test "the ref comes from the argument, else DEPLOY_REF" {
  hook '{"status": 202, "body": ""}'
  run -0 "$RUN_BASH" "$TRIGGER" refs/heads/production
  DEPLOY_REF=refs/tags/v1.2.3 run -0 "$RUN_BASH" "$TRIGGER"
  [ "$(mock_requests | grep -c 'refs/heads/production')" -eq 1 ]
  [ "$(mock_requests | grep -c 'refs/tags/v1.2.3')" -eq 1 ]
}

@test "the webhook URL is never printed" {
  hook '{"status": 200, "body": "ok"}'
  run -0 "$RUN_BASH" "$TRIGGER"
  assert_lacks "$SECRET"
  hook '{"status": 404, "body": "no such hook"}'
  run -1 "$RUN_BASH" "$TRIGGER"
  assert_lacks "$SECRET"
}

@test "a 3xx is a refusal: exit 1 at once, no retry" {
  hook '{"status": 302, "headers": {"Location": "/elsewhere"}, "body": "moved elsewhere"}'
  run -1 --separate-stderr "$RUN_BASH" "$TRIGGER"
  assert_has "attempt 1/3: HTTP 302 moved elsewhere"
  output="$stderr" assert_has "declined the deploy of refs/heads/main (HTTP 302)"
  [ "$(mock_count)" -eq 1 ]
}

@test "a 4xx is a refusal too" {
  hook '{"status": 403, "body": "forbidden"}'
  run -1 "$RUN_BASH" "$TRIGGER"
  [ "$(mock_count)" -eq 1 ]
}

@test "5xx is retried until it is accepted" {
  hook '[{"status": 503, "body": "busy"}, {"status": 502, "body": "busy"}, {"status": 200, "body": "ok"}]'
  run -0 "$RUN_BASH" "$TRIGGER"
  assert_has "attempt 2/3: HTTP 502 busy"
  assert_has "attempt 3/3: HTTP 200 ok"
  [ "$(mock_count)" -eq 3 ]
}

@test "5xx on every attempt fails after the last retry" {
  hook '{"status": 503, "body": "busy"}'
  run -1 --separate-stderr "$RUN_BASH" "$TRIGGER"
  [ "$(mock_count)" -eq 3 ]
  output="$stderr" assert_has "did not accept the deploy of refs/heads/main after 3 attempts"
}

@test "DEPLOY_RETRY_DELAYS=\"\" means one attempt; a bad value is refused" {
  hook '{"status": 503, "body": "busy"}'
  DEPLOY_RETRY_DELAYS="" run -1 "$RUN_BASH" "$TRIGGER"
  [ "$(mock_count)" -eq 1 ]
  DEPLOY_RETRY_DELAYS="1 x" run -2 "$RUN_BASH" "$TRIGGER"
  DEPLOY_WEBHOOK_TIMEOUT=soon run -2 "$RUN_BASH" "$TRIGGER"
  [ "$(mock_count)" -eq 1 ]
}

@test "no answer at all is retried, and reported without curl's own text" {
  DEPLOY_WEBHOOK_URL="https://127.0.0.1:9/deploy/$SECRET" DEPLOY_RETRY_DELAYS="0" run -1 "$RUN_BASH" "$TRIGGER"
  assert_has "attempt 1/2: no answer (curl exit 7)"
  assert_has "attempt 2/2: no answer (curl exit 7)"
  assert_lacks "127.0.0.1"
}

@test "the platform's answer is printed without control characters" {
  hook "$(python3 -c 'import json; print(json.dumps({"status": 200, "body": "ok \u001b[2J done"}))')"
  run -0 "$RUN_BASH" "$TRIGGER"
  assert_lacks $'\033'
  assert_has "HTTP 200 ok  [2J done"
}

@test "in GitHub Actions the error is an annotation on stdout" {
  hook '{"status": 404, "body": "gone"}'
  GITHUB_ACTIONS=true run -1 --separate-stderr "$RUN_BASH" "$TRIGGER"
  assert_has "::error::The deploy platform declined the deploy of refs/heads/main (HTTP 404)."
  [ -z "$stderr" ]
}

@test "runs under the bash on PATH as well as under RUN_BASH" {
  hook '{"status": 200, "body": "ok"}'
  run -0 bash "$TRIGGER"
}
