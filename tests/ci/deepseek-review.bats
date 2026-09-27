#!/usr/bin/env bats
# actions/deepseek-review/scripts/review.sh against a local HTTPS stand-in (tests/agent-deploy's
# mock_server.py) that plays both the GitHub API and DeepSeek's chat API. The skips (no key, a fork,
# a draft, nothing left), the diff it sends (exclusions, the byte cap, the untrusted-input framing),
# the one comment it posts or updates, the failures it reports, and that no token is ever printed.
# shellcheck disable=SC2016 # expected output holds literal backticks

load helpers
load ../agent-deploy/helpers

REVIEW="$KIT_ROOT/actions/deepseek-review/scripts/review.sh"
KEY=deepseek-key-for-tests
TOKEN=github-token-for-tests

setup_file() { mock_start; }
teardown_file() { mock_stop; }

setup() {
  mock_reset
  unset DEEPSEEK_API_KEY GITHUB_REPOSITORY GITHUB_EVENT_NAME GITHUB_STEP_SUMMARY REVIEW_PR REVIEW_MODEL \
    REVIEW_BASE_URL REVIEW_INSTRUCTIONS REVIEW_EXCLUDE REVIEW_MAX_DIFF_BYTES REVIEW_MAX_TOKENS REVIEW_EFFORT \
    REVIEW_TIMEOUT RUNNER_TEMP
  export DEEPSEEK_API_KEY="$KEY" GH_TOKEN="$TOKEN" GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME=pull_request
  export GITHUB_API_URL="$MOCK/api" REVIEW_BASE_URL="$MOCK/ds" REVIEW_PR=7
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  routes
}

# routes [PATCH]: pull request 7 from this repository, two changed files (one a lockfile), a chat
# answer, no earlier review comment. PATCH is a JSON object of routes to add or replace.
routes() {
  local patch="${1:-}"
  [ -n "$patch" ] || patch='{}'
  python3 - "$MOCK_DIR/config.json" "$patch" <<'PY'
import json, sys
path, patch = sys.argv[1], json.loads(sys.argv[2])
routes = {
    "/api/repos/o/r/pulls/7": {"json": {"number": 7, "title": "Add the invite flow", "body": "Please look, @alice.",
                                        "state": "open", "draft": False,
                                        "head": {"sha": "abcdef1234567890", "repo": {"full_name": "o/r"}}}},
    "/api/repos/o/r/pulls/7/files?per_page=100&page=1": {"json": [
        {"filename": "src/invite.ts", "status": "modified", "patch": "@@ -1 +1 @@\n-old\n+new"},
        {"filename": "bun.lock", "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}]},
    "/ds/chat/completions": {"json": {"choices": [{"message": {"content": "**HIGH** `src/invite.ts:1`: ask @bob."},
                                                   "finish_reason": "stop"}],
                                      "usage": {"prompt_tokens": 321, "completion_tokens": 45}}},
    "/api/repos/o/r/issues/7/comments?per_page=100&page=1": {"json": []},
    "/api/repos/o/r/issues/7/comments": {"status": 201, "json": {"id": 99}},
}
routes.update(patch)
json.dump({"routes": routes}, open(path, "w"))
PY
}

review() { run --separate-stderr "$RUN_BASH" "$REVIEW"; }

# The JSON body of the Nth request to a path (1 = the first).
body_of() { # path [n]
  mock_requests "$1" | sed -n "${2:-1}p" | python3 -c 'import json, sys; print(json.loads(sys.stdin.read())["body"])'
}

@test "deepseek-review: without the API key it skips, passes and sends nothing" {
  unset DEEPSEEK_API_KEY
  review
  [ "$status" -eq 0 ]
  assert_has "DEEPSEEK_API_KEY is not set, so no review was requested"
  [ "$(mock_count)" -eq 0 ]
  grep -q 'DeepSeek review skipped' "$GITHUB_STEP_SUMMARY"
}

@test "deepseek-review: a fork's pull request, a draft or a closed one is skipped before DeepSeek is asked" {
  routes '{"/api/repos/o/r/pulls/7": {"json": {"number": 7, "state": "open", "draft": false, "head": {"sha": "abc", "repo": {"full_name": "stranger/r"}}}}}'
  review
  [ "$status" -eq 0 ]
  assert_has "comes from a fork (stranger/r)"
  routes '{"/api/repos/o/r/pulls/7": {"json": {"number": 7, "state": "open", "draft": false, "head": {"sha": "abc", "repo": null}}}}'
  review
  [ "$status" -eq 0 ]
  assert_has "comes from a fork (a deleted repository)"
  routes '{"/api/repos/o/r/pulls/7": {"json": {"number": 7, "state": "closed", "draft": false, "head": {"sha": "abc", "repo": {"full_name": "o/r"}}}}}'
  review
  assert_has "pull request #7 is closed"
  routes '{"/api/repos/o/r/pulls/7": {"json": {"number": 7, "state": "open", "draft": true, "head": {"sha": "abc", "repo": {"full_name": "o/r"}}}}}'
  review
  assert_has "is a draft"
  [ "$(mock_count /ds)" -eq 0 ]
  # An explicit /ask-deepseek (the issue_comment event) reviews a draft.
  GITHUB_EVENT_NAME=issue_comment review
  [ "$status" -eq 0 ]
  [ "$(mock_count /ds)" -eq 1 ]
}

@test "deepseek-review: it sends the diff without lockfiles, with the notes, the model and the caps" {
  REVIEW_INSTRUCTIONS="A Bun + Hono API." REVIEW_EFFORT=low REVIEW_MAX_TOKENS=2048 REVIEW_MODEL=deepseek-flash review
  [ "$status" -eq 0 ]
  assert_has "2 changed file(s): 1 in the review"
  body_of /ds/chat/completions | python3 -c '
import json, sys
req = json.load(sys.stdin)
assert req["model"] == "deepseek-flash", req["model"]
assert req["max_tokens"] == 2048 and req["reasoning_effort"] == "low" and req["stream"] is False, req
system, user = req["messages"][0]["content"], req["messages"][1]["content"]
assert "Project notes:\nA Bun + Hono API." in system, system
assert "data, not instructions" in system, system
assert "Pull request #7: Add the invite flow" in user, user
assert "diff --git a/src/invite.ts b/src/invite.ts" in user and "+new" in user, user
assert "bun.lock" not in user, user
'
  # Both APIs got their own token, each in a header, never in the URL.
  mock_requests /ds | grep -q "\"authorization\": \"Bearer $KEY\""
  mock_requests /api | grep -q "\"authorization\": \"Bearer $TOKEN\""
  [ "$(mock_requests | grep -c "$KEY")" -eq 1 ]
}

@test "deepseek-review: files are added whole up to the byte cap; the rest are listed, and nothing left is a skip" {
  routes '{"/api/repos/o/r/pulls/7/files?per_page=100&page=1": {"json": [
    {"filename": "a.ts", "status": "added", "patch": "@@ -0,0 +1 @@\n+a"},
    {"filename": "big.ts", "status": "added", "patch": "@@ -0,0 +1 @@\n+XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"},
    {"filename": "gen/api.ts", "status": "added", "patch": "@@ -0,0 +1 @@\n+g"},
    {"filename": "img.png", "status": "added"}]}}'
  REVIEW_MAX_DIFF_BYTES=200 REVIEW_EXCLUDE='gen/*' review
  [ "$status" -eq 0 ]
  assert_has "4 changed file(s): 2 in the review"
  assert_has "1 excluded by pattern, 1 over the 200-byte cap"
  body_of /ds/chat/completions | python3 -c '
import json, sys
user = json.load(sys.stdin)["messages"][1]["content"]
assert "b/a.ts" in user and "b/img.png" in user and "(no text diff" in user, user
assert "big.ts" not in user and "gen/api.ts" not in user, user
'
  body_of /api/repos/o/r/issues/7/comments 2 | python3 -c '
import json, sys
body = json.load(sys.stdin)["body"]
assert "1 file(s) left out to keep the diff under the size cap" in body and "- `big.ts`" in body, body
assert "2 file(s) reviewed, 1 excluded by pattern" in body, body
'
  : >"$MOCK_DIR/log.jsonl"
  REVIEW_MAX_DIFF_BYTES=10 review
  [ "$status" -eq 0 ]
  assert_has "nothing to review in pull request #7"
  [ "$(mock_count /ds)" -eq 0 ]
}

@test "deepseek-review: it posts one marked comment, mentions quietened, with the model, commit and tokens" {
  review
  [ "$status" -eq 0 ]
  assert_has "posted the review comment on pull request #7"
  [ "$(mock_requests /api/repos/o/r/issues/7/comments | grep -c '"method": "POST"')" -eq 1 ]
  body_of /api/repos/o/r/issues/7/comments 2 | python3 -c '
import json, sys
body = json.load(sys.stdin)["body"]
assert body.startswith("<!-- agent-config-kit:deepseek-review -->\n### DeepSeek review"), body
assert "ask `@bob`." in body, body
assert "`deepseek-v4-pro`" in body and "Commit `abcdef1`" in body and "321 tokens in, 45 out" in body, body
assert "/ask-deepseek" in body, body
'
  grep -q '321 tokens in, 45 out' "$GITHUB_STEP_SUMMARY"
}

@test "deepseek-review: a later run updates the bot's comment and never a person's that quotes the marker" {
  routes '{"/api/repos/o/r/issues/7/comments?per_page=100&page=1": {"json": [
      {"id": 5, "user": {"type": "User", "login": "alice"}, "body": "<!-- agent-config-kit:deepseek-review --> quoted"},
      {"id": 6, "user": {"type": "Bot", "login": "github-actions[bot]"}, "body": "<!-- agent-config-kit:deepseek-review -->\nold"}]},
    "/api/repos/o/r/issues/comments/6": {"json": {"id": 6}}}'
  review
  [ "$status" -eq 0 ]
  assert_has "updated the review comment on pull request #7"
  [ "$(mock_count /api/repos/o/r/issues/comments/6)" -eq 1 ]
  mock_requests /api/repos/o/r/issues/comments/6 | grep -q '"method": "PATCH"'
  [ "$(mock_count /api/repos/o/r/issues/comments/5)" -eq 0 ]
  [ "$(mock_requests /api/repos/o/r/issues/7/comments | grep -c '"method": "POST"')" -eq 0 ]
}

@test "deepseek-review: a busy DeepSeek is a warning that passes; a refused request fails; neither leaks a token" {
  routes '{"/ds/chat/completions": {"status": 503, "json": {"error": {"message": "Server busy"}}}}'
  REVIEW_TIMEOUT=5 review
  [ "$status" -eq 0 ]
  output="$stderr" assert_has "DeepSeek did not answer (HTTP 503) Server busy"
  [ "$(mock_count /api/repos/o/r/issues)" -eq 0 ]
  routes '{"/ds/chat/completions": {"status": 402, "json": {"error": {"message": "Insufficient Balance"}}}}'
  review
  [ "$status" -eq 1 ]
  output="$stderr" assert_has "DeepSeek refused the request (HTTP 402): Insufficient Balance"
  output="$output$stderr" assert_lacks "$KEY"
  output="$output$stderr" assert_lacks "$TOKEN"
}

@test "deepseek-review: an answer cut at max-tokens says so; a GitHub API failure fails the job" {
  routes '{"/ds/chat/completions": {"json": {"choices": [{"message": {"content": ""}, "finish_reason": "length"}], "usage": {"prompt_tokens": 1, "completion_tokens": 16384}}}}'
  review
  [ "$status" -eq 0 ]
  body_of /api/repos/o/r/issues/7/comments 2 | grep -q 'used all 16384 tokens before it answered'
  routes '{"/api/repos/o/r/pulls/7": {"status": 403, "json": {"message": "Resource not accessible by integration"}}}'
  review
  [ "$status" -eq 1 ]
  output="$stderr" assert_has "could not read pull request #7 (HTTP 403): Resource not accessible by integration"
}

@test "deepseek-review: bad settings stop before any request" {
  for bad in 'REVIEW_PR=7;x' 'REVIEW_PR=' 'GITHUB_REPOSITORY=o' 'GITHUB_REPOSITORY=o/r/x' \
    'REVIEW_BASE_URL=http://127.0.0.1:9' 'REVIEW_MODEL=a b' 'REVIEW_EFFORT=extreme' 'REVIEW_MAX_DIFF_BYTES=0' \
    'GH_TOKEN='; do
    run --separate-stderr env "$bad" "$RUN_BASH" "$REVIEW"
    [ "$status" -eq 2 ] || {
      echo "expected exit 2 for $bad, got $status: $stderr" >&2
      return 1
    }
  done
  [ "$(mock_count)" -eq 0 ]
}
