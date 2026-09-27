#!/usr/bin/env bats
# verify-deploy.sh against a local HTTPS stand-in for the site and the GitHub API.
# shellcheck disable=SC2030,SC2031 # each @test is its own subshell: its exports are meant to stay there

load helpers

setup_file() { mock_start; }
teardown_file() { mock_stop; }

setup() {
  mock_reset
  mock_site
  export GITHUB_API_URL="$MOCK/api"
  cd "$BATS_TEST_TMPDIR" || return 1
}

@test "--help lists every check and exits 0" {
  run -0 "$RUN_BASH" "$VERIFY" --help
  for name in http canonical indexing robots sitemap hsts csp nosniff framing referrer deploy; do
    assert_has "  $name "
  done
}

@test "usage errors exit 2 before any request" {
  run -2 "$RUN_BASH" "$VERIFY"
  assert_has "--url is required"
  run -2 "$RUN_BASH" "$VERIFY" --url ftp://example.com/
  run -2 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --pr 7 --since 2026-01-10T10:00:00Z
  run -2 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --since yesterday
  run -2 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --skip bogus
  run -2 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --timeout 0
  run -2 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo not-a-repo
  run -2 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --frobnicate
  [ "$(mock_count)" -eq 0 ]
}

@test "a healthy site with a deployment after the merge passes every check" {
  export GH_TOKEN=test-token-5d1c9e
  run -0 --separate-stderr "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  [ "$(printf '%s\n' "$output" | grep -c '^  PASS ')" -eq 11 ]
  assert_has "result: pass (11 passed, 0 failed, 0 warnings, 0 skipped)"
  assert_check deploy PASS
  assert_has "deployment #12 created 2026-01-10T10:05:00Z, after the merge of #7 at 2026-01-10T10:00:00Z; status success; commit aaaaaaa"
}

@test "the hosts it will contact are printed before the checks" {
  export GH_TOKEN=test-token-5d1c9e
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  [ "${lines[0]}" = "verify-deploy: $MOCK/" ]
  [ "${lines[1]}" = "  network: GET $MOCK/ (up to 5 redirects), then /robots.txt and the sitemap on the host it lands on; GitHub API $MOCK/api for o/r (token from GH_TOKEN)" ]
}

@test "the token goes only to the GitHub API and is never printed" {
  export GH_TOKEN=test-token-5d1c9e
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_lacks "test-token-5d1c9e"
  [ "$(mock_requests /api/ | grep -c '"authorization": "Bearer test-token-5d1c9e"')" -eq "$(mock_count /api/)" ]
  [ "$(mock_count /api/)" -ge 3 ]
  [ "$(mock_requests | grep -v '"path": "/api/' | grep -c authorization || true)" -eq 0 ]
}

@test "without an env token it asks gh for the API host's token" {
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"%s/gh-args"\necho gh-token-77f2\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/gh"
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  [ "$(cat "$BATS_TEST_TMPDIR/gh-args")" = "auth token --hostname 127.0.0.1" ]
  assert_has "for o/r (token from the GitHub CLI)"
  assert_lacks "gh-token-77f2"
  [ "$(mock_requests /api/ | grep -c 'Bearer gh-token-77f2')" -ge 3 ]
}

@test "no token at all: anonymous API calls, said up front" {
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "for o/r (no token)"
  [ "$(mock_requests | grep -c authorization || true)" -eq 0 ]
}

@test "a token is never sent to a plain-http API base" {
  export GH_TOKEN=test-token-5d1c9e GITHUB_API_URL="http://127.0.0.1:9/api"
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "GitHub API http://127.0.0.1:9/api for o/r (no token)"
  assert_check deploy FAIL
}

@test "--json prints one object on stdout and the host list on stderr" {
  export GH_TOKEN=test-token-5d1c9e
  run -0 --separate-stderr "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7 --json
  printf '%s' "$output" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["result"] == "pass", data
assert [c["name"] for c in data["checks"]] == ["http", "canonical", "indexing", "robots", "sitemap",
    "hsts", "csp", "nosniff", "framing", "referrer", "deploy"]
assert data["counts"] == {"pass": 11, "fail": 0, "warn": 0, "skip": 0}
'
  output="$stderr" assert_has "network: GET $MOCK/"
}

@test "http: a 500 fails, and the checks that need the page are skipped" {
  mock_site '{"/": {"status": 500}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check http FAIL
  assert_has "HTTP 500 at $MOCK/"
  assert_check canonical SKIP
  assert_check indexing SKIP
}

@test "http: a 200 whose body never completes fails, and the page checks are skipped" {
  mock_site '{"/": {"short_body": true}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --timeout 10
  assert_check http FAIL
  assert_has "200 at $MOCK/, but the response did not complete:"
  assert_check canonical SKIP
}

@test "http: a redirect to the page is followed and counted" {
  mock_site '{"/old": {"status": 301, "headers": {"Location": "__BASE__/"}, "body": ""}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/old"
  assert_has "PASS  http       200 at $MOCK/ after 1 redirect"
}

@test "security headers: each missing one fails on its own line" {
  mock_site '{"/": {"headers": {"Content-Security-Policy": null, "X-Content-Type-Options": null, "Strict-Transport-Security": null}}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check hsts FAIL
  assert_check csp FAIL
  assert_check nosniff FAIL
  assert_check framing FAIL
  assert_check referrer PASS
}

@test "security headers: X-Frame-Options covers framing, report-only CSP is a warning" {
  mock_site '{"/": {"headers": {"Content-Security-Policy": null, "Content-Security-Policy-Report-Only": "default-src '"'self'"'", "X-Frame-Options": "SAMEORIGIN"}}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check csp WARN
  assert_check framing PASS
  assert_has "X-Frame-Options SAMEORIGIN"
}

@test "security headers: HSTS max-age=0 fails; referrer unsafe-url fails, missing warns" {
  mock_site '{"/": {"headers": {"Strict-Transport-Security": "max-age=0", "Referrer-Policy": "unsafe-url"}}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check hsts FAIL
  assert_check referrer FAIL
  mock_site '{"/": {"headers": {"Referrer-Policy": null}}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check referrer WARN
}

@test "canonical: missing, relative, another host, or two of them all fail" {
  local head_open='<!doctype html><html><head>' head_close='</head><body>x</body></html>'
  for link in '' '<link rel="canonical" href="/">' '<link rel="canonical" href="https://staging.example.test/">' \
    '<link rel="canonical" href="__BASE__/"><link rel="canonical" href="__BASE__/a">'; do
    mock_site "$(python3 -c 'import json,sys; print(json.dumps({"/": {"body": sys.argv[1] + sys.argv[2] + sys.argv[3]}}))' "$head_open" "$link" "$head_close")"
    run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
    assert_check canonical FAIL
  done
}

@test "canonical: a Link header counts, and --canonical demands an exact match" {
  mock_site '{"/": {"body": "<html><head></head><body>x</body></html>", "headers": {"Link": "<__BASE__/>; rel=\"canonical\""}}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check canonical PASS
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --canonical "$MOCK/home"
  assert_has "expected $MOCK/home"
}

@test "indexing: noindex on production fails, from a meta tag or a header" {
  mock_site '{"/": {"body": "<html><head><link rel=\"canonical\" href=\"__BASE__/\"><meta name=\"robots\" content=\"noindex, follow\"></head></html>"}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check indexing FAIL
  mock_site '{"/": {"headers": {"X-Robots-Tag": "noindex"}}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "production page says noindex: X-Robots-Tag: noindex"
}

@test "--expect-noindex: a staging deploy must not be indexable, and needs no sitemap" {
  mock_site '{"/": {"headers": {"X-Robots-Tag": "noindex"}}, "/sitemap.xml": null}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --expect-noindex
  assert_check indexing PASS
  assert_check sitemap SKIP
  mock_site '{"/sitemap.xml": null}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --expect-noindex
  assert_has "this staging or preview deploy is indexable"
}

@test "robots: missing, served as HTML, or disallowing everything fails on production" {
  mock_site '{"/robots.txt": null}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "FAIL  robots     /robots.txt: HTTP 404"
  mock_site '{"/robots.txt": {"headers": {"Content-Type": "text/html"}}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "served as text/html"
  mock_site '{"/robots.txt": {"body": "User-agent: *\nDisallow: /\n"}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "disallows / for every crawler"
}

@test "robots: a Disallow: / for one named crawler is not a block for all" {
  mock_site '{"/robots.txt": {"body": "User-agent: ExampleBot\nDisallow: /\n\nUser-agent: *\nAllow: /\nSitemap: __BASE__/sitemap.xml\n"}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check robots PASS
}

@test "sitemap: the one robots.txt names is the one fetched" {
  mock_site '{"/robots.txt": {"body": "User-agent: *\nAllow: /\nSitemap: __BASE__/maps/index.xml\n"}, "/maps/index.xml": {"status": 200, "headers": {"Content-Type": "application/xml"}, "body": "<sitemapindex><sitemap><loc>__BASE__/maps/1.xml</loc></sitemap></sitemapindex>"}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "PASS  sitemap    /maps/index.xml: 1 URL"
  [ "$(mock_count /sitemap.xml)" -eq 0 ]
}

@test "sitemap: one robots.txt places on another host is named, never fetched" {
  # 127.0.0.2 would answer on this machine: the test proves it is never asked, not that it is down.
  mock_site '{"/robots.txt": {"body": "User-agent: *\nAllow: /\nSitemap: https://127.0.0.2:9/private.xml\n"}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check sitemap WARN
  assert_has "robots.txt names 1 sitemap on another host, not fetched (first: https://127.0.0.2:9/private.xml)"
  [ "$(mock_count /sitemap.xml)" -eq 0 ]
  mock_site '{"/robots.txt": {"body": "User-agent: *\nAllow: /\nSitemap: https://127.0.0.2:9/a.xml\nSitemap: __BASE__/sitemap.xml\n"}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "/sitemap.xml: 2 URLs"
  [ "$(mock_count /sitemap.xml)" -eq 1 ]
}

@test "sitemap: a 404, an HTML soft 404, or URLs on another host are reported" {
  mock_site '{"/sitemap.xml": null}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "FAIL  sitemap    /sitemap.xml: HTTP 404"
  mock_site '{"/sitemap.xml": {"headers": {"Content-Type": "text/html"}, "body": "<html>Not found</html>"}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "200 but not a sitemap (text/html)"
  mock_site '{"/sitemap.xml": {"body": "<urlset><url><loc>https://elsewhere.example.test/</loc></url></urlset>"}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_check sitemap WARN
}

@test "deploy: the newest successful deployment wins, whatever the list order" {
  mock_site '{"/api/repos/o/r/deployments": {"json": [
    {"id": 12, "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "created_at": "2026-01-10T10:05:00Z"},
    {"id": 11, "sha": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "created_at": "2026-01-10T09:00:00Z"},
    {"id": 13, "sha": "cccccccccccccccccccccccccccccccccccccccc", "created_at": "2026-01-10T11:00:00Z"}]},
    "/api/repos/o/r/deployments/13/statuses": {"json": [{"id": 9, "state": "in_progress", "created_at": "2026-01-10T11:00:05Z"}]}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "deployment #12 created 2026-01-10T10:05:00Z, after the merge"
  assert_has "; a newer deployment #13 is in_progress"
}

@test "deploy: order in the list never decides which deployment is newest" {
  # Listed as success, in_progress, failure; by created_at it is in_progress (11:40), failure
  # (10:20), success (10:05). Taking the list as given, or reversed, reports the wrong neighbour.
  mock_site '{"/api/repos/o/r/deployments": {"json": [
    {"id": 12, "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "created_at": "2026-01-10T10:05:00Z"},
    {"id": 14, "sha": "cccccccccccccccccccccccccccccccccccccccc", "created_at": "2026-01-10T11:40:00Z"},
    {"id": 13, "sha": "dddddddddddddddddddddddddddddddddddddddd", "created_at": "2026-01-10T10:20:00Z"}]},
    "/api/repos/o/r/deployments/14/statuses": {"json": [{"id": 8, "state": "in_progress", "created_at": "2026-01-10T11:40:05Z"}]},
    "/api/repos/o/r/deployments/13/statuses": {"json": [{"id": 7, "state": "failure", "created_at": "2026-01-10T10:24:00Z"}]}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "deployment #12 created 2026-01-10T10:05:00Z, after the merge"
  assert_has "; a newer deployment #14 is in_progress"
}

@test "deploy: with only older deployments, the newest by time is the one named" {
  mock_site '{"/api/repos/o/r/deployments": {"json": [
    {"id": 9, "sha": "b", "created_at": "2026-01-09T08:00:00Z"},
    {"id": 11, "sha": "b", "created_at": "2026-01-10T09:00:00Z"},
    {"id": 10, "sha": "b", "created_at": "2026-01-09T20:00:00Z"}]}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "the newest is #11 at 2026-01-10T09:00:00Z"
}

@test "deploy: the newest status of a deployment decides, whatever the status order" {
  mock_site '{"/api/repos/o/r/deployments/12/statuses": {"json": [
    {"id": 2, "state": "in_progress", "created_at": "2026-01-10T10:05:10Z"},
    {"id": 4, "state": "failure", "created_at": "2026-01-10T10:09:00Z"},
    {"id": 3, "state": "success", "created_at": "2026-01-10T10:08:00Z"}]}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "deployment #12 created 2026-01-10T10:05:00Z is failure"
}

@test "deploy: nothing after the merge is a failure, never a pass" {
  mock_site '{"/api/repos/o/r/deployments": {"json": [{"id": 11, "sha": "b", "created_at": "2026-01-10T09:00:00Z"}]}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "no deployment created after the merge of #7 at 2026-01-10T10:00:00Z; the newest is #11 at 2026-01-10T09:00:00Z"
}

@test "deploy: a deployment still in progress is not finished" {
  mock_site '{"/api/repos/o/r/deployments/12/statuses": {"json": [{"id": 2, "state": "in_progress", "created_at": "2026-01-10T10:05:10Z"}]}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "deployment #12 created 2026-01-10T10:05:00Z is in_progress: not finished, or it failed"
}

@test "deploy: an unmerged pull request fails" {
  mock_site '{"/api/repos/o/r/pulls/7": {"json": {"number": 7, "merged_at": null}}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "pull request #7 is not merged"
}

@test "deploy: another commit passes only when it contains the merge commit" {
  mock_site '{"/api/repos/o/r/deployments": {"json": [{"id": 12, "sha": "dddddddddddddddddddddddddddddddddddddddd", "created_at": "2026-01-10T10:05:00Z"}]},
    "/api/repos/o/r/compare/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...dddddddddddddddddddddddddddddddddddddddd": {"json": {"status": "ahead"}}}'
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "commit ddddddd"
  mock_site '{"/api/repos/o/r/deployments": {"json": [{"id": 12, "sha": "dddddddddddddddddddddddddddddddddddddddd", "created_at": "2026-01-10T10:05:00Z"}]},
    "/api/repos/o/r/compare/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...dddddddddddddddddddddddddddddddddddddddd": {"json": {"status": "behind"}}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "is of ddddddd, which does not contain the merge commit aaaaaaa (behind)"
}

@test "deploy: a repository with no deployments says how to skip the check" {
  mock_site '{"/api/repos/o/r/deployments": {"json": []}}'
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "o/r has no GitHub deployments"
  assert_has "pass --skip deploy"
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7 --skip deploy
  assert_check deploy SKIP
}

@test "deploy: API errors fail with the reason, and server text cannot inject escapes" {
  mock_site "$(python3 -c 'import json; print(json.dumps({"/api/repos/o/r/pulls/7": {"status": 404, "json": {"message": "Not \u001b[31mFound"}}}))')"
  run -1 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --pr 7
  assert_has "GitHub API /repos/o/r/pulls/7: HTTP 404 (not found; a private repository needs GH_TOKEN; Not [31mFound)"
  assert_lacks $'\033'
}

@test "deploy: --since and --environment shape the query" {
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r --since 2026-01-10T10:00:00Z --environment production
  assert_has "deployment #12 to production created 2026-01-10T10:05:00Z, after 2026-01-10T10:00:00Z"
  [ "$(mock_count '/api/repos/o/r/deployments?per_page=100&environment=production')" -eq 1 ]
  [ "$(mock_count /api/repos/o/r/pulls)" -eq 0 ]
}

@test "deploy: skipped when there is no repository or no merge to compare with" {
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/"
  assert_has "SKIP  deploy     no --repo, and origin is not a github.com remote"
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --repo o/r
  assert_has "SKIP  deploy     pass --pr N or --since TIME"
  [ "$(mock_count /api/)" -eq 0 ]
}

@test "deploy: the repository comes from a github.com origin remote" {
  git init -q "$BATS_TEST_TMPDIR/app"
  git -C "$BATS_TEST_TMPDIR/app" remote add origin git@github.com:o/r.git
  cd "$BATS_TEST_TMPDIR/app"
  run -0 "$RUN_BASH" "$VERIFY" --url "$MOCK/" --pr 7
  assert_has "for o/r (no token)"
  assert_check deploy PASS
}

@test "runs under the bash on PATH as well as under RUN_BASH" {
  run -0 bash "$VERIFY" --url "$MOCK/"
  assert_has "result: pass"
}
