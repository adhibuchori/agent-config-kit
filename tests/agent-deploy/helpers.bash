# shellcheck shell=bash
# Helpers for the agent-deploy tests: a local HTTPS server (mock_server.py) that plays the live
# site, the deploy webhook and the GitHub API. No test touches the network.

bats_require_minimum_version 1.5.0

# The .bats files that load this file read these paths.
# shellcheck disable=SC2034
{
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  DEPLOY_PLUGIN="$REPO_ROOT/plugins/agent-deploy"
  DEPLOY_TEMPLATES="$DEPLOY_PLUGIN/templates/deploy"
  VERIFY="$DEPLOY_TEMPLATES/scripts/deploy/verify-deploy.sh"
  TRIGGER="$DEPLOY_TEMPLATES/scripts/deploy/trigger-deploy.sh"
  CORE="$REPO_ROOT/plugins/agent-core"
}
# The bash that runs the scripts. /bin/bash is 3.2 on macOS, so the suite proves bash 3.2 there;
# DEPLOY_BASH=bash runs it under the bash on PATH instead.
RUN_BASH="${DEPLOY_BASH:-/bin/bash}"
[ -x "$RUN_BASH" ] || RUN_BASH="$(command -v bash)"

# setup_file: generate a throwaway certificate, start the server, export MOCK (its base URL),
# MOCK_DIR and CURL_CA_BUNDLE (so curl trusts the certificate without any flag in the scripts).
mock_start() {
  command -v openssl >/dev/null 2>&1 || skip "openssl is needed for the local TLS server"
  command -v python3 >/dev/null 2>&1 || skip "python3 is needed"
  command -v curl >/dev/null 2>&1 || skip "curl is needed"
  export MOCK_DIR="$BATS_FILE_TMPDIR/mock"
  mkdir -p "$MOCK_DIR"
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=127.0.0.1" \
    -addext "subjectAltName=IP:127.0.0.1" \
    -keyout "$MOCK_DIR/key.pem" -out "$MOCK_DIR/cert.pem" >/dev/null 2>&1 ||
    skip "openssl could not make a test certificate"
  printf '{}\n' >"$MOCK_DIR/config.json"
  : >"$MOCK_DIR/log.jsonl"
  python3 "$BATS_TEST_DIRNAME/mock_server.py" "$MOCK_DIR/config.json" "$MOCK_DIR/port" \
    "$MOCK_DIR/log.jsonl" "$MOCK_DIR/cert.pem" "$MOCK_DIR/key.pem" 3>&- >/dev/null 2>"$MOCK_DIR/server.err" &
  printf '%s\n' "$!" >"$MOCK_DIR/pid"
  local i=0
  # Up to 30 s: a busy CI runner can take a while to start python3 and load ssl.
  while [ ! -s "$MOCK_DIR/port" ] && [ "$i" -lt 300 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -s "$MOCK_DIR/port" ] || {
    echo "mock server did not start; its stderr:" >&2
    cat "$MOCK_DIR/server.err" >&2
    return 1
  }
  local port
  port="$(cat "$MOCK_DIR/port")"
  export MOCK="https://127.0.0.1:$port"
  export CURL_CA_BUNDLE="$MOCK_DIR/cert.pem"
}

mock_stop() {
  if [ -n "${MOCK_DIR:-}" ] && [ -f "$MOCK_DIR/pid" ]; then
    local pid
    pid="$(cat "$MOCK_DIR/pid")"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

# setup: every test starts from an empty request log, a clean environment and no stray gh.
mock_reset() {
  : >"$MOCK_DIR/log.jsonl"
  unset GH_TOKEN GITHUB_TOKEN GITHUB_API_URL GITHUB_ACTIONS DEPLOY_WEBHOOK_URL DEPLOY_REF \
    DEPLOY_RETRY_DELAYS DEPLOY_WEBHOOK_TIMEOUT
  # A gh that is never signed in, first on PATH, so the host machine's gh is never asked.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# mock_routes JSON: replace the server's routes with exactly this object.
mock_routes() {
  python3 - "$MOCK_DIR/config.json" "$MOCK" "$1" <<'PY'
import json, sys
path, base, routes = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "w") as handle:
    json.dump({"routes": json.loads(routes.replace("__BASE__", base))}, handle)
PY
}

# mock_site [PATCH]: a healthy production site plus a GitHub API where PR 7 merged at 10:00 and
# deployment 12 (created 10:05, success, the merge commit) followed it. PATCH is a JSON object of
# routes: null removes a route, an object is merged into the route (its "headers" key by key,
# where null removes a header), and a list replaces the route. __BASE__ becomes the server URL.
mock_site() {
  local patch="${1:-}"
  [ -n "$patch" ] || patch='{}'
  python3 - "$MOCK_DIR/config.json" "$MOCK" "$patch" <<'PY'
import json, sys
path, base, patch = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
merge = "a" * 40
routes = {
    "/": {"status": 200,
          "headers": {"Strict-Transport-Security": "max-age=63072000; includeSubDomains",
                      "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'",
                      "X-Content-Type-Options": "nosniff",
                      "Referrer-Policy": "strict-origin-when-cross-origin"},
          "body": '<!doctype html><html lang="en"><head><title>Home</title>'
                  '<link rel="canonical" href="__BASE__/"></head><body>ok</body></html>'},
    "/robots.txt": {"status": 200, "headers": {"Content-Type": "text/plain"},
                    "body": "User-agent: *\nAllow: /\n\nSitemap: __BASE__/sitemap.xml\n"},
    "/sitemap.xml": {"status": 200, "headers": {"Content-Type": "application/xml"},
                     "body": '<?xml version="1.0" encoding="UTF-8"?>\n'
                             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
                             "<url><loc>__BASE__/</loc></url><url><loc>__BASE__/about</loc></url>"
                             "</urlset>"},
    "/api/repos/o/r/pulls/7": {"json": {"number": 7, "merged_at": "2026-01-10T10:00:00Z",
                                        "merge_commit_sha": merge}},
    "/api/repos/o/r/deployments": {"json": [
        {"id": 11, "sha": "b" * 40, "environment": "production", "created_at": "2026-01-10T09:00:00Z"},
        {"id": 12, "sha": merge, "environment": "production", "created_at": "2026-01-10T10:05:00Z"}]},
    "/api/repos/o/r/deployments/11/statuses": {"json": [
        {"id": 1, "state": "success", "created_at": "2026-01-10T09:03:00Z"}]},
    "/api/repos/o/r/deployments/12/statuses": {"json": [
        {"id": 3, "state": "success", "created_at": "2026-01-10T10:08:00Z"},
        {"id": 2, "state": "in_progress", "created_at": "2026-01-10T10:05:10Z"}]},
}
for key, value in patch.items():
    if value is None:
        routes.pop(key, None)
    elif isinstance(value, dict) and isinstance(routes.get(key), dict):
        route = routes[key]
        for field, item in value.items():
            if field == "headers":
                headers = route.setdefault("headers", {})
                for name, header in item.items():
                    if header is None:
                        headers.pop(name, None)
                    else:
                        headers[name] = header
            elif item is None:
                route.pop(field, None)
            else:
                route[field] = item
    else:
        routes[key] = value
with open(path, "w") as handle:
    json.dump({"routes": json.loads(json.dumps(routes).replace("__BASE__", base))}, handle)
PY
}

# mock_requests [PATH-PREFIX]: the logged requests, one JSON object per line.
mock_requests() {
  python3 - "$MOCK_DIR/log.jsonl" "${1:-}" <<'PY'
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    entry = json.loads(line)
    if entry["path"].startswith(sys.argv[2]):
        print(json.dumps(entry, sort_keys=True))
PY
}

# mock_count [PATH-PREFIX]: how many requests reached the server.
mock_count() {
  mock_requests "${1:-}" | grep -c . || true
}

# shellcheck disable=SC2154 # output is set by bats' run
# Assertions are plain commands on purpose: under bash 3.2, a failing [[ ]] that is not the last
# command of a test does not trip errexit, so it would never fail the test.

# assert_has TEXT: $output contains TEXT.
assert_has() {
  case "$output" in
    *"$1"*) return 0 ;;
  esac
  printf 'expected the output to contain:\n  %s\n--- output ---\n%s\n' "$1" "$output" >&2
  return 1
}

# assert_lacks TEXT: $output does not contain TEXT.
assert_lacks() {
  case "$output" in
    *"$1"*)
      printf 'expected the output not to contain:\n  %s\n--- output ---\n%s\n' "$1" "$output" >&2
      return 1
      ;;
  esac
  return 0
}

# assert_check NAME STATUS: the status column (PASS, FAIL, WARN, SKIP) of one verify-deploy check.
assert_check() {
  local got
  got="$(printf '%s\n' "$output" | awk -v name="$1" '$2 == name { print $1; exit }')"
  if [ "$got" != "$2" ]; then
    printf 'check %s: expected %s, got %s\n--- output ---\n%s\n' "$1" "$2" "${got:-nothing}" "$output" >&2
    return 1
  fi
}
