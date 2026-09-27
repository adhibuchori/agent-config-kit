#!/usr/bin/env bats
# serve.mjs and a11y.mjs: the local server the browser checks use, and the accessibility runner
# with stand-in checkers (tests/agent-fe-nextjs-static/helpers.bash). The stand-ins fetch every URL
# they are given, so a passing run also proves the server answered 200 for each page.

load helpers

setup() { make_site; }

# Requests paths from startServer() in-process: one "<path> <status> <content-type>" line each.
serve_probe() {
  node --input-type=module -e "
    import { startServer } from '$CHECKS/serve.mjs';
    import { loadConfig, openSite } from '$CHECKS/lib/site.mjs';
    const root = process.cwd();
    const s = await startServer(openSite(root, loadConfig(root)), 0);
    for (const p of process.argv.slice(1)) {
      const r = await fetch(s.url + p);
      console.log(p, r.status, r.headers.get('content-type'), r.headers.get('content-encoding') || 'identity');
    }
    await s.close();
  " "$@"
}

@test "serve: built pages, assets and the 404 page are served like a static host" {
  run -0 --separate-stderr serve_probe / /about /blog/hello /images/hero.png /robots.txt /nope
  [[ "$output" == *"/ 200 text/html"* ]] || false
  [[ "$output" == *"/about 200 text/html"* ]] || false
  [[ "$output" == *"/blog/hello 200 text/html"* ]] || false
  [[ "$output" == *"/images/hero.png 200 image/png"* ]] || false
  [[ "$output" == *"/robots.txt 200 text/plain"* ]] || false
  [[ "$output" == *"/nope 404 text/html"* ]] || false
}

@test "serve: text is gzipped for a client that accepts it, images are sent as they are" {
  run -0 --separate-stderr serve_probe / /_next/static/chunks/main.js /images/hero.png
  [[ "$output" == *"/ 200 text/html; charset=utf-8 gzip"* ]] || false
  [[ "$output" == *"/_next/static/chunks/main.js 200 text/javascript; charset=utf-8 gzip"* ]] || false
  [[ "$output" == *"/images/hero.png 200 image/png identity"* ]] || false
}

@test "serve: a path that climbs out of the build is not served" {
  echo '{"secret": true}' >package.json
  run -0 --separate-stderr serve_probe /..%2fpackage.json /%2e%2e/package.json /_next/../../package.json
  [[ "$output" != *" 200 "* ]] || false
  [ "$(grep -c ' 404 ' <<<"$output")" -eq 3 ]
}

@test "serve: the ssg-with-endpoints layout serves .next pages and metadata routes by URL type" {
  to_ssg_layout
  run -0 --separate-stderr serve_probe / /about /robots.txt /sitemap.xml /_next/static/chunks/app.css
  [[ "$output" == *"/ 200 text/html"* ]] || false
  [[ "$output" == *"/robots.txt 200 text/plain"* ]] || false
  [[ "$output" == *"/sitemap.xml 200 application/xml"* ]] || false
  [[ "$output" == *"/_next/static/chunks/app.css 200 text/css"* ]] || false
}

@test "serve: the CLI prints its ready line, answers, and stops cleanly on SIGTERM" {
  node "$CHECKS/serve.mjs" --port 0 >"$BATS_TEST_TMPDIR/serve.log" 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do grep -q 'ready on' "$BATS_TEST_TMPDIR/serve.log" && break; sleep 0.1; done
  url="$(sed -n 's/.*ready on \(http:[^ ]*\)$/\1/p' "$BATS_TEST_TMPDIR/serve.log")"
  [ -n "$url" ]
  run -0 node -e 'fetch(process.argv[1]).then((r) => { console.log(r.status); })' "${url}about"
  [ "$output" = "200" ]
  kill -TERM "$pid"
  wait "$pid"
}

@test "serve: a bad port or no build is a usage error" {
  run -2 --separate-stderr node "$CHECKS/serve.mjs" --port nope
  [[ "$stderr" == *"--port must be a whole number"* ]] || false
  rm -rf out
  run -2 --separate-stderr node "$CHECKS/serve.mjs" --port 0
  [[ "$stderr" == *"out does not exist: build the site first"* ]] || false
}

@test "a11y: no checker installed is exit 2 with what to install, never a pass" {
  check a11y
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no accessibility checker in node_modules/.bin"*"pa11y-ci"*"@axe-core/cli"* ]] || false
}

@test "a11y: pa11y-ci runs over every indexable page with the axe runner and WCAG2AA" {
  stub_pa11y
  check a11y
  [ "$status" -eq 0 ]
  for p in / /about /blog/hello /id; do [[ "$output" == *"STUB 200 $p"$'\n'* ]] || false; done
  [[ "$output" != *"STUB 200 /404"* ]] || false
  [[ "$output" == *'"standard":"WCAG2AA"'* ]] || false
  [[ "$output" == *'"runners":["axe"]'* ]] || false
  [[ "$output" == *"a11y: ok - 0 error(s)"* ]] || false
}

@test "a11y: pa11y-ci exit 2 (errors found) fails the check; exit 1 (could not run) is exit 2" {
  stub_pa11y
  STUB_EXIT=2 check a11y
  [ "$status" -eq 1 ]
  [[ "$output" == *"a11y: ERROR pa11y-ci: reported accessibility errors"* ]] || false
  STUB_EXIT=1 check a11y
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"pa11y-ci could not run (exit 1)"* ]] || false
}

@test "a11y: the project's .pa11yci.json defaults are kept, its urls are not" {
  stub_pa11y
  printf '%s\n' '{"defaults": {"timeout": 5000, "standard": "WCAG2AAA"}, "urls": ["https://elsewhere.example.net/"]}' >.pa11yci.json
  check a11y
  [ "$status" -eq 0 ]
  [[ "$output" == *'"timeout":5000'* ]] || false
  [[ "$output" == *'"standard":"WCAG2AAA"'* ]] || false
  [[ "$output" != *"elsewhere.example.net"* ]] || false
}

@test "a11y: --only and a11y.exclude narrow the pages; an unknown page is a usage error" {
  stub_pa11y
  check a11y --only /about
  [ "$status" -eq 0 ]
  [ "$(grep -c '^STUB 200' <<<"$output")" -eq 1 ]
  set_config a11y.exclude '["/blog/**"]'
  check a11y
  [[ "$output" != *"STUB 200 /blog/hello"* ]] || false
  [[ "$output" == *"STUB 200 /about"* ]] || false
  check a11y --only /careers
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"not a built page (or excluded): /careers"* ]] || false
}

@test "a11y: axe results are read from its JSON, so a violation fails and a crash is exit 2" {
  stub_axe
  check a11y --tool axe
  [ "$status" -eq 0 ]
  STUB_VIOLATION=1 check a11y --tool axe
  [ "$status" -eq 1 ]
  [[ "$output" == *"a11y: ERROR /about: image-alt (critical): Images must have alternate text; 2 element(s)"* ]] || false
  STUB_EXIT=4 check a11y --tool axe
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"axe could not run (exit 4)"* ]] || false
}

@test "a11y: an unknown --tool, or a named tool that is not installed, is a usage error" {
  check a11y --tool lighthouse
  [ "$status" -eq 2 ]
  stub_pa11y
  check a11y --tool axe
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"node_modules/.bin/axe not found"* ]] || false
}

@test "a11y: the ssg-with-endpoints layout is served and checked the same way" {
  to_ssg_layout
  stub_pa11y
  check a11y
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB 200 /about"* ]] || false
  [[ "$output" == *"ssg-with-endpoints build"* ]] || false
}
